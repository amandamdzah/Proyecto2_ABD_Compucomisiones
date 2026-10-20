USE COMPUCOMISIONES;
GO

-- Cálculo: se debe implementar un procedimiento almacenado que «corra el cálculo de
-- comisiones» para un periodo dado. A partir de las facturas cobradas dentro de ese periodo y
-- de las participaciones registradas en ellas, deberá aplicar los filtros del plan vigente para
-- cada dupla (vendedor, rol) a fin de determinar qué parte de cada factura entra en el cálculo,
-- obtener la comisión de cada vendedor y el reconocimiento que perciben los supervisores
-- sobre lo generado por sus vendedores, y registrar el cálculo de comisiones de cada persona
-- para ese periodo.

CREATE OR ALTER PROCEDURE sp_calculo_comisiones
    @id_periodo_calculo INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @inicio DATE, @cierre DATE;

    -- validar que el periodo exista y obtener su rango de fechas
    SELECT 
        @inicio = fecha_inicio, 
        @cierre = fecha_cierre
    FROM periodo
    WHERE id_periodo = @id_periodo_calculo;

    IF @inicio IS NULL
    BEGIN
        RAISERROR ('El periodo para el cálculo de comisiones no existe.', 16, 1);
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        -- calcular comisiones de vendedores y reconocimiento de supervisores
        WITH LineasFacturasCobradas AS (
            -- obtenemos las facturas cobradas en el periodo, sus renglones y participaciones
            SELECT 
                f.numero AS numero_factura,
                CAST(f.fecha_cobro AS DATE) AS fecha_cobro_date,
                f.codigo_cliente,
                df.codigo_producto,
                df.cantidad,
                df.monto,
                df.motivo,
                pf.id_vendedor,
                pf.id_rol,
                pf.porcentaje AS porcentaje_participacion,
                pc.codigo AS id_plan,
                pc.tasa AS tasa_plan,
                pc.base AS base_plan,
                pc.admite_descuentos
            FROM factura AS f
            INNER JOIN detalle_factura AS df 
                ON df.numero_factura = f.numero
            INNER JOIN participacion_factura AS pf 
                ON pf.numero_factura = f.numero
            -- Buscamos el plan vigente para la dupla (vendedor, rol) al momento del cobro
            CROSS APPLY (
                SELECT TOP 1 apv.id_plan
                FROM asignacion_plan_vendedor AS apv
                WHERE apv.id_vendedor = pf.id_vendedor
                  AND apv.id_rol = pf.id_rol
                  AND apv.fecha_desde <= CAST(f.fecha_cobro AS DATE)
                ORDER BY apv.fecha_desde DESC
            ) AS plan_vigente
            INNER JOIN plan_comision AS pc 
                ON pc.codigo = plan_vigente.id_plan
            WHERE f.situacion = 'cobrada'
              AND CAST(f.fecha_cobro AS DATE) BETWEEN @inicio AND @cierre
              -- Filtro de descuentos según configuración del plan:
              -- Si admite_descuentos = 0, ignoramos montos negativos o renglones de descuento
              AND (pc.admite_descuentos = 1 OR (df.monto >= 0 AND df.motivo NOT LIKE '%descuento%'))
        ),
        ComisionesPorParticipacion AS (
            -- determinamos la base imponible según el plan y calculamos la comisión del vendedor
            SELECT 
                lfc.numero_factura,
                lfc.fecha_cobro_date,
                lfc.id_vendedor,
                CAST(
                    SUM(
                        CASE 
                            WHEN lfc.base_plan = 'ingreso'  THEN lfc.monto
                            WHEN lfc.base_plan = 'margen'   THEN lfc.monto -- Ajustar si se agrega columna costo
                            WHEN lfc.base_plan = 'cantidad' THEN CAST(lfc.cantidad AS DECIMAL(12,2))
                            ELSE 0
                        END
                        * (lfc.porcentaje_participacion / 100.0)
                        * (lfc.tasa_plan / 100.0)
                    ) AS DECIMAL(12,2)
                ) AS comision_vendedor
            FROM LineasFacturasCobradas AS lfc
            GROUP BY 
                lfc.numero_factura,
                lfc.fecha_cobro_date,
                lfc.id_vendedor
        ),
        ReconocimientoSupervisores AS (
            -- calculamos lo que percibe el supervisor asignado al vendedor en la fecha de cobro
            SELECT 
                ha.id_supervisor,
                CAST(
                    SUM(cpp.comision_vendedor * (ha.porcentaje_reconocimiento / 100.0)) 
                    AS DECIMAL(12,2)
                ) AS monto_supervision
            FROM ComisionesPorParticipacion AS cpp
            INNER JOIN historial_asignacion AS ha
                ON ha.id_vendedor = cpp.id_vendedor
               AND cpp.fecha_cobro_date BETWEEN ha.fecha_desde AND ISNULL(ha.fecha_hasta, '9999-12-31')
            GROUP BY 
                ha.id_supervisor
        ),
        TotalesVendedores AS (
            SELECT 
                id_vendedor AS id_persona,
                SUM(comision_vendedor) AS monto_ventas_propias
            FROM ComisionesPorParticipacion
            GROUP BY id_vendedor
        ),
        ConsolidadoPeriodo AS (
            -- unificamos vendedores y supervisores activos en un solo resultado por persona
            SELECT 
                COALESCE(v.id_persona, s.id_supervisor) AS id_persona,
                ISNULL(v.monto_ventas_propias, 0) AS monto_ventas_propias,
                ISNULL(s.monto_supervision, 0) AS monto_supervision
            FROM TotalesVendedores AS v
            FULL OUTER JOIN ReconocimientoSupervisores AS s
                ON v.id_persona = s.id_supervisor
            INNER JOIN persona AS p
                ON p.id_persona = COALESCE(v.id_persona, s.id_supervisor)
            WHERE p.estado = 1 -- Solo personas activas
        )
        -- registrar o actualizar el cálculo del periodo en calculo_comision
        MERGE INTO calculo_comision AS destino
        USING ConsolidadoPeriodo AS origen
            ON destino.id_periodo = @id_periodo_calculo 
           AND destino.id_persona = origen.id_persona
        WHEN MATCHED THEN
            UPDATE SET 
                destino.monto_ventas_propias = origen.monto_ventas_propias,
                destino.monto_supervision = origen.monto_supervision,
                destino.estado = 'Calculado'
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (id_periodo, id_persona, monto_ventas_propias, monto_supervision, estado)
            VALUES (@id_periodo_calculo, origen.id_persona, origen.monto_ventas_propias, origen.monto_supervision, 'Calculado');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH
END;
GO


CREATE OR ALTER PROCEDURE sp_registrar_pagos
    @id_periodo_pago INT,
    @id_periodo_calculo INT,
    @fecha_pago DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @inicio DATE, @cierre DATE, @ultimo_id INT;

    -- fechas del periodo de pago
    SELECT @inicio = fecha_inicio, @cierre = fecha_cierre
    FROM periodo
    WHERE id_periodo = @id_periodo_pago;

    IF @inicio IS NULL
    BEGIN
        RAISERROR ('El periodo de pago no existe.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM calculo_comision WHERE id_periodo = @id_periodo_calculo)
    BEGIN
        RAISERROR ('No hay un cálculo de comisiones registrado para ese periodo.', 16, 1);
        RETURN;
    END

    -- si no mandan fecha se usa el cierre
    IF @fecha_pago IS NULL
        SET @fecha_pago = @cierre;

    IF @fecha_pago < @inicio OR @fecha_pago > @cierre
    BEGIN
        RAISERROR ('La fecha de pago tiene que estar dentro del periodo de pago.', 16, 1);
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        -- ultimo id para seguir la numeracion
        SELECT @ultimo_id = ISNULL(MAX(id_pago), 0) FROM pago;

        -- un pago por persona con comision
        INSERT INTO pago (id_pago, id_periodo, id_persona, fecha, monto, estado)
        SELECT
            @ultimo_id + ROW_NUMBER() OVER (ORDER BY cc.id_persona),
            @id_periodo_pago,
            cc.id_persona,
            @fecha_pago,
            cc.monto_ventas_propias + cc.monto_supervision,
            'pendiente'
        FROM calculo_comision AS cc
        WHERE cc.id_periodo = @id_periodo_calculo
          AND cc.estado = 'calculado'
          AND cc.monto_ventas_propias + cc.monto_supervision > 0;

        -- activos pagado, inactivos retenido
        UPDATE pg
        SET pg.estado = CASE WHEN p.estado = 1 THEN 'pagado' ELSE 'retenido' END
        FROM pago AS pg
        INNER JOIN persona AS p ON pg.id_persona = p.id_persona
        WHERE pg.id_periodo = @id_periodo_pago
          AND pg.estado = 'pendiente';

        -- retenidos que ya estan activos
        UPDATE pg
        SET pg.estado = 'pagado'
        FROM pago AS pg
        INNER JOIN persona AS p ON pg.id_persona = p.id_persona
        WHERE pg.id_periodo = @id_periodo_pago
          AND pg.estado = 'retenido'
          AND p.estado = 1;

        -- el calculo queda igual que su pago
        UPDATE cc
        SET cc.estado = pg.estado
        FROM calculo_comision AS cc
        INNER JOIN pago AS pg ON cc.id_persona = pg.id_persona
        WHERE cc.id_periodo = @id_periodo_calculo
          AND pg.id_periodo = @id_periodo_pago
          AND cc.estado IN ('calculado', 'retenido');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    -- pagos del periodo
    SELECT pg.id_pago, p.nombre, p.apellidos, pg.fecha, pg.monto, pg.estado
    FROM pago AS pg
    INNER JOIN persona AS p ON pg.id_persona = p.id_persona
    WHERE pg.id_periodo = @id_periodo_pago
    ORDER BY pg.id_pago;
END;
GO

USE COMPUCOMISIONES;
GO

CREATE OR ALTER PROCEDURE comisiones_schema.sp_calculo_comisiones
    @id_periodo_calculo INT
AS
BEGIN
    SET NOCOUNT ON;

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

    -- un periodo que ya se pago no se vuelve a calcular
    IF EXISTS (SELECT 1 FROM calculo_comision WHERE id_periodo = @id_periodo_calculo AND estado IN ('pagado', 'retenido'))
    BEGIN
        RAISERROR ('Ese periodo ya tiene pagos, no se puede volver a calcular.', 16, 1);
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        DELETE FROM calculo_comision WHERE id_periodo = @id_periodo_calculo;

        SELECT
            pf.id_vendedor,
            CAST(f.fecha_emision AS DATE) AS fecha_venta,
            CAST(CASE WHEN pc.base = 'cantidad'
                      THEN comisiones_schema.fn_base_comisionable(pf.numero_factura, pc.codigo) * pc.tasa
                      ELSE comisiones_schema.fn_base_comisionable(pf.numero_factura, pc.codigo) * pc.tasa / 100
                 END * pf.porcentaje / 100 AS DECIMAL(12,2)) AS comision
        INTO #comisiones
        FROM factura AS f
        INNER JOIN participacion_factura AS pf ON pf.numero_factura = f.numero
        CROSS APPLY (
            SELECT TOP 1 apv.id_plan
            FROM asignacion_plan_vendedor AS apv
            WHERE apv.id_vendedor = pf.id_vendedor
              AND apv.id_rol = pf.id_rol
              AND apv.fecha_desde <= CAST(f.fecha_emision AS DATE)
            ORDER BY apv.fecha_desde DESC
        ) AS plan_vigente
        INNER JOIN plan_comision AS pc ON pc.codigo = plan_vigente.id_plan
        WHERE f.situacion = 'cobrada'
          AND CAST(f.fecha_cobro AS DATE) BETWEEN @inicio AND @cierre;

        INSERT INTO calculo_comision (id_periodo, id_persona, monto_ventas_propias, monto_supervision, estado)
        SELECT @id_periodo_calculo, t.id_persona, SUM(t.ventas), SUM(t.supervision), 'calculado'
        FROM (
            SELECT id_vendedor AS id_persona, comision AS ventas, 0 AS supervision
            FROM #comisiones

            UNION ALL

            SELECT ha.id_supervisor, 0, CAST(c.comision * ha.porcentaje_reconocimiento / 100 AS DECIMAL(12,2))
            FROM #comisiones AS c
            INNER JOIN historial_asignacion AS ha
                ON ha.id_vendedor = c.id_vendedor
               AND c.fecha_venta >= ha.fecha_desde
               AND (ha.fecha_hasta IS NULL OR c.fecha_venta <= ha.fecha_hasta)
        ) AS t
        GROUP BY t.id_persona;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    SELECT cc.id_persona, p.nombre, p.apellidos, cc.monto_ventas_propias, cc.monto_supervision, cc.estado
    FROM calculo_comision AS cc
    INNER JOIN persona AS p ON p.id_persona = cc.id_persona
    WHERE cc.id_periodo = @id_periodo_calculo
    ORDER BY cc.id_persona;
END;
GO

CREATE OR ALTER PROCEDURE comisiones_schema.sp_registrar_pagos
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

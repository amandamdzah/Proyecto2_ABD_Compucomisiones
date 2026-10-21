USE COMPUCOMISIONES;
GO

-- 1. Control de la participación en la factura: sobre el registro de las participaciones, debe
-- garantizar que la suma de los porcentajes de participación de los vendedores de una
-- misma factura nunca supere el 100%, rechazando toda inserción o modificación que
-- rompa esa regla.

-- participacion_factura(numero_factura: INT, id_vendedor: INT, id_rol: INT, porcentaje: DECIMAL(5,2))

CREATE OR ALTER TRIGGER comisiones_schema.pct_participacion_factura
ON comisiones_schema.participacion_factura
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT (UPDATE(porcentaje) OR UPDATE(numero_factura))
        RETURN;

    IF EXISTS (
        SELECT 1
        FROM participacion_factura AS p
        WHERE p.numero_factura IN (SELECT DISTINCT numero_factura FROM inserted)
        GROUP BY p.numero_factura
        HAVING SUM(p.porcentaje) > 100.00
    )
    BEGIN
        RAISERROR ('La suma de los porcentajes de participación de los vendedores de una misma factura no puede superar el 100%%.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END;
GO

-- 2. Integridad de la cadena de supervisión: debe impedir que un supervisor quede
-- registrado como su propio jefe y que se formen ciclos en la línea de mando (por ejemplo,
-- que una persona dependa de otra y esta, directa o indirectamente, termine dependiendo
-- de la primera).

-- supervisor(id_supervisor: INT, zona: VARCHAR(50), id_supervisor_jefe: INT)

CREATE OR ALTER TRIGGER comisiones_schema.trg_supervisor_evitar_ciclo
ON comisiones_schema.supervisor
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(id_supervisor_jefe)
        RETURN;

    IF EXISTS (
        SELECT 1
        FROM inserted
        WHERE id_supervisor = id_supervisor_jefe
    )
    BEGIN
        RAISERROR ('Operación cancelada: Un supervisor no puede ser su propio jefe.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END

    DECLARE @hay_ciclo BIT = 0;

        WITH linea_de_mando AS (
            SELECT
                i.id_supervisor,
                i.id_supervisor_jefe,
                CAST('/' + CAST(i.id_supervisor AS VARCHAR(MAX)) + '/' AS VARCHAR(MAX)) AS ruta,
                0 AS tiene_ciclo
            FROM inserted AS i
            WHERE i.id_supervisor_jefe IS NOT NULL

            UNION ALL

            SELECT
                padre.id_supervisor,
                padre.id_supervisor_jefe,
                lm.ruta + CAST(padre.id_supervisor AS VARCHAR(MAX)) + '/',
                CASE
                    WHEN lm.ruta LIKE '%/' + CAST(padre.id_supervisor AS VARCHAR(MAX)) + '/%' THEN 1
                    ELSE 0
                END
            FROM supervisor AS padre
            INNER JOIN linea_de_mando AS lm ON lm.id_supervisor_jefe = padre.id_supervisor
            WHERE lm.tiene_ciclo = 0
        )
        SELECT TOP 1 @hay_ciclo = 1
        FROM linea_de_mando
        WHERE tiene_ciclo = 1;

        IF @hay_ciclo = 1
        BEGIN
            RAISERROR ('Operación cancelada: Se detectó una dependencia circular en la jerarquía de supervisores.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END;
END;
GO

-- 3. Recupero por devolución: cuando una factura se anula (devolución) y el plan bajo el
-- cual se reconoció la comisión admite descuentos, debe retraer del cálculo de comisiones
-- la parte que ya se había reconocido a quienes participaron en esa factura

CREATE OR ALTER TRIGGER comisiones_schema.trg_recupero_devolucion
ON comisiones_schema.factura
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(situacion)
        RETURN;

    SELECT
        pf.id_vendedor,
        CAST(d.fecha_emision AS DATE) AS fecha_venta,
        CAST(d.fecha_cobro AS DATE) AS fecha_cobro,
        CAST(CASE WHEN pc.base = 'cantidad'
                  THEN comisiones_schema.fn_base_comisionable(pf.numero_factura, pc.codigo) * pc.tasa
                  ELSE comisiones_schema.fn_base_comisionable(pf.numero_factura, pc.codigo) * pc.tasa / 100
             END * pf.porcentaje / 100 AS DECIMAL(12,2)) AS comision
    INTO #retraer
    FROM inserted AS i
    INNER JOIN deleted AS d ON d.numero = i.numero
    INNER JOIN participacion_factura AS pf ON pf.numero_factura = i.numero
    CROSS APPLY (
        SELECT TOP 1 apv.id_plan
        FROM asignacion_plan_vendedor AS apv
        WHERE apv.id_vendedor = pf.id_vendedor
          AND apv.id_rol = pf.id_rol
          AND apv.fecha_desde <= CAST(d.fecha_emision AS DATE)
        ORDER BY apv.fecha_desde DESC
    ) AS plan_vigente
    INNER JOIN plan_comision AS pc ON pc.codigo = plan_vigente.id_plan
    WHERE d.situacion = 'cobrada'
      AND i.situacion = 'anulada'
      AND pc.admite_descuentos = 1;

    IF NOT EXISTS (SELECT 1 FROM #retraer)
        RETURN;

    UPDATE cc
    SET cc.monto_ventas_propias = CASE WHEN cc.monto_ventas_propias > r.total
                                       THEN cc.monto_ventas_propias - r.total ELSE 0 END
    FROM calculo_comision AS cc
    INNER JOIN (
        SELECT p.id_periodo, r.id_vendedor AS id_persona, SUM(r.comision) AS total
        FROM #retraer AS r
        INNER JOIN periodo AS p ON r.fecha_cobro BETWEEN p.fecha_inicio AND p.fecha_cierre
        GROUP BY p.id_periodo, r.id_vendedor
    ) AS r ON r.id_periodo = cc.id_periodo AND r.id_persona = cc.id_persona;

    UPDATE cc
    SET cc.monto_supervision = CASE WHEN cc.monto_supervision > s.total
                                    THEN cc.monto_supervision - s.total ELSE 0 END
    FROM calculo_comision AS cc
    INNER JOIN (
        SELECT p.id_periodo, ha.id_supervisor AS id_persona,
               SUM(CAST(r.comision * ha.porcentaje_reconocimiento / 100 AS DECIMAL(12,2))) AS total
        FROM #retraer AS r
        INNER JOIN historial_asignacion AS ha
            ON ha.id_vendedor = r.id_vendedor
           AND r.fecha_venta >= ha.fecha_desde
           AND (ha.fecha_hasta IS NULL OR r.fecha_venta <= ha.fecha_hasta)
        INNER JOIN periodo AS p ON r.fecha_cobro BETWEEN p.fecha_inicio AND p.fecha_cierre
        GROUP BY p.id_periodo, ha.id_supervisor
    ) AS s ON s.id_periodo = cc.id_periodo AND s.id_persona = cc.id_persona;
END;
GO

-- 4. Solo las personas activas pueden incorporarse como vendedores en nuevas facturas

CREATE OR ALTER TRIGGER comisiones_schema.trg_participacion_vendedor_activo
ON comisiones_schema.participacion_factura
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        INNER JOIN persona AS p ON p.id_persona = i.id_vendedor
        WHERE p.estado = 0
          AND NOT EXISTS (SELECT 1 FROM deleted AS d
                          WHERE d.numero_factura = i.numero_factura AND d.id_vendedor = i.id_vendedor)
    )
    BEGIN
        RAISERROR ('Solo las personas activas pueden incorporarse como vendedores en nuevas facturas.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END;
GO

-- 5. Solo las personas activas pueden recibir nuevas asignaciones de plan

CREATE OR ALTER TRIGGER comisiones_schema.trg_asignacion_vendedor_activo
ON comisiones_schema.asignacion_plan_vendedor
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        INNER JOIN persona AS p ON p.id_persona = i.id_vendedor
        WHERE p.estado = 0
          AND NOT EXISTS (SELECT 1 FROM deleted AS d
                          WHERE d.id_vendedor = i.id_vendedor AND d.id_rol = i.id_rol AND d.fecha_desde = i.fecha_desde)
    )
    BEGIN
        RAISERROR ('Solo las personas activas pueden recibir nuevas asignaciones de plan.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END;
GO

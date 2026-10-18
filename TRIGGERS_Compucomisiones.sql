-- 1. Control de la participación en la factura: sobre el registro de las participaciones, debe
-- garantizar que la suma de los porcentajes de participación de los vendedores de una
-- misma factura nunca supere el 100%, rechazando toda inserción o modificación que
-- rompa esa regla.

-- participacion_factura(numero_factura: INT, id_vendedor: INT, id_rol: INT, porcentaje: DECIMAL(5,2))

CREATE OR ALTER TRIGGER pct_participacion_factura
ON participacion_factura
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

CREATE OR ALTER TRIGGER trg_supervisor_evitar_ciclo
ON supervisor
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

    IF EXISTS (
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
        SELECT 1
        FROM linea_de_mando
        WHERE tiene_ciclo = 1
    )
    BEGIN
        RAISERROR ('Operación cancelada: Se detectó una dependencia circular en la jerarquía de supervisores.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END;
GO

-- 3. Recupero por devolución: cuando una factura se anula (devolución) y el plan bajo el
-- cual se reconoció la comisión admite descuentos, debe retraer del cálculo de comisiones
-- la parte que ya se había reconocido a quienes participaron en esa factura

CREATE OR ALTER TRIGGER trg_recupero_devolucion
ON factura
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(situacion)
        RETURN;

    WITH FacturasAnuladas AS (
        SELECT
            i.numero AS numero_factura,
            CAST(i.fecha_emision AS DATE) AS fecha_ref,
            SUM(df.monto) AS total_factura,
            SUM(df.cantidad) AS total_cantidad
        FROM inserted i
        INNER JOIN deleted d ON i.numero = d.numero
        INNER JOIN detalle_factura df ON i.numero = df.numero_factura
        WHERE d.situacion = 'cobrada'
          AND i.situacion = 'anulada'
        GROUP BY i.numero, CAST(i.fecha_emision AS DATE)
    ),
    RetraccionVendedores AS (
        SELECT
            fa.numero_factura,
            fa.fecha_ref,
            pf.id_vendedor,
            CASE
                WHEN pc.base IN ('ingreso', 'margen')
                    THEN fa.total_factura * (pf.porcentaje / 100.0) * (pc.tasa / 100.0)
                WHEN pc.base = 'cantidad'
                    THEN fa.total_cantidad * (pf.porcentaje / 100.0) * pc.tasa
                ELSE 0
            END AS comision_a_retraer
        FROM FacturasAnuladas fa
        INNER JOIN participacion_factura pf ON fa.numero_factura = pf.numero_factura
        CROSS APPLY (
            SELECT TOP 1 apv.id_plan
            FROM asignacion_plan_vendedor apv
            WHERE apv.id_vendedor = pf.id_vendedor
              AND apv.id_rol = pf.id_rol
              AND apv.fecha_desde <= fa.fecha_ref
            ORDER BY apv.fecha_desde DESC
        ) plan_vigente
        INNER JOIN plan_comision pc ON plan_vigente.id_plan = pc.codigo
        WHERE pc.admite_descuentos = 1
    )
    UPDATE cc
    SET cc.monto_ventas_propias = cc.monto_ventas_propias -agrupado.total_retraer
    FROM calculo_comision cc
    INNER JOIN (
        SELECT
            p.id_periodo,
            rv.id_vendedor AS id_persona,
            SUM(rv.comision_a_retraer) AS total_retraer
        FROM RetraccionVendedores rv
        INNER JOIN periodo p ON rv.fecha_ref BETWEEN p.fecha_inicio AND p.fecha_cierre
        GROUP BY p.id_periodo, rv.id_vendedor
    ) agrupado ON cc.id_periodo = agrupado.id_periodo
              AND cc.id_persona = agrupado.id_persona;

    WITH FacturasAnuladas AS (
        SELECT
            i.numero AS numero_factura,
            CAST(i.fecha_emision AS DATE) AS fecha_ref,
            SUM(df.monto) AS total_factura,
            SUM(df.cantidad) AS total_cantidad
        FROM inserted i
        INNER JOIN deleted d ON i.numero = d.numero
        INNER JOIN detalle_factura df ON i.numero = df.numero_factura
        WHERE d.situacion = 'cobrada'
          AND i.situacion = 'anulada'
        GROUP BY i.numero, CAST(i.fecha_emision AS DATE)
    ),
    RetraccionSupervisores AS (
        SELECT
            p.id_periodo,
            ha.id_supervisor AS id_persona,
            SUM(
                (CASE
                    WHEN pc.base IN ('ingreso', 'margen')
                        THEN fa.total_factura * (pf.porcentaje / 100.0) * (pc.tasa / 100.0)
                    WHEN pc.base = 'cantidad'
                        THEN fa.total_cantidad * (pf.porcentaje / 100.0) * pc.tasa
                    ELSE 0
                END) * (ha.porcentaje_reconocimiento / 100.0)
            ) AS total_retraer_sup
        FROM FacturasAnuladas fa
        INNER JOIN participacion_factura pf ON fa.numero_factura = pf.numero_factura
        CROSS APPLY (
            SELECT TOP 1 apv.id_plan
            FROM asignacion_plan_vendedor apv
            WHERE apv.id_vendedor = pf.id_vendedor
              AND apv.id_rol = pf.id_rol
              AND apv.fecha_desde <= fa.fecha_ref
            ORDER BY apv.fecha_desde DESC
        ) plan_vigente
        INNER JOIN plan_comision pc ON plan_vigente.id_plan = pc.codigo
        INNER JOIN historial_asignacion ha ON pf.id_vendedor = ha.id_vendedor
            AND fa.fecha_ref >= ha.fecha_desde
            AND (ha.fecha_hasta IS NULL OR fa.fecha_ref <= ha.fecha_hasta)
        INNER JOIN periodo p ON fa.fecha_ref BETWEEN p.fecha_inicio AND p.fecha_cierre
        WHERE pc.admite_descuentos = 1
        GROUP BY p.id_periodo, ha.id_supervisor
    )
    UPDATE cc
    SET cc.monto_supervision = cc.monto_supervision - rs.total_retraer_sup
    FROM calculo_comision cc
    INNER JOIN RetraccionSupervisores rs ON cc.id_periodo = rs.id_periodo
                                        AND cc.id_persona = rs.id_persona;
END;
GO

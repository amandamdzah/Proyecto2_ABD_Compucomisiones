USE COMPUCOMISIONES;
GO

-- base comisionable de una factura segun los filtros del plan

CREATE OR ALTER FUNCTION comisiones_schema.fn_base_comisionable
(
    @numero_factura INT,
    @id_plan INT
)
RETURNS DECIMAL(12,2)
AS
BEGIN
    DECLARE @base VARCHAR(20), @resultado DECIMAL(12,2);

    SELECT @base = base FROM plan_comision WHERE codigo = @id_plan;

    SELECT @resultado = SUM(CASE
                                WHEN @base = 'ingreso' THEN df.monto
                                WHEN @base = 'margen' AND df.monto > df.costo THEN df.monto - df.costo
                                WHEN @base = 'cantidad' THEN df.cantidad
                                ELSE 0
                            END)
    FROM detalle_factura AS df
    INNER JOIN producto AS p ON p.codigo = df.codigo_producto
    WHERE df.numero_factura = @numero_factura
      AND (NOT EXISTS (SELECT 1 FROM filtro_plan AS fp WHERE fp.id_plan = @id_plan AND fp.tipo_filtro = 'producto')
           OR EXISTS (SELECT 1 FROM filtro_plan AS fp WHERE fp.id_plan = @id_plan AND fp.tipo_filtro = 'producto'
                      AND fp.codigo_producto = df.codigo_producto))
      AND (NOT EXISTS (SELECT 1 FROM filtro_plan AS fp WHERE fp.id_plan = @id_plan AND fp.tipo_filtro = 'categoria')
           OR EXISTS (SELECT 1 FROM filtro_plan AS fp WHERE fp.id_plan = @id_plan AND fp.tipo_filtro = 'categoria'
                      AND fp.categoria = p.categoria))
      AND (NOT EXISTS (SELECT 1 FROM filtro_plan AS fp WHERE fp.id_plan = @id_plan AND fp.tipo_filtro = 'motivo')
           OR EXISTS (SELECT 1 FROM filtro_plan AS fp WHERE fp.id_plan = @id_plan AND fp.tipo_filtro = 'motivo'
                      AND fp.motivo = df.motivo));

    RETURN ISNULL(@resultado, 0);
END;
GO

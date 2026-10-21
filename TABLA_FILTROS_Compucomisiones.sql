USE COMPUCOMISIONES;
GO

CREATE TABLE comisiones_schema.filtro_plan (
    id_plan INT NOT NULL,
    orden INT NOT NULL,
    tipo_filtro VARCHAR(20) NOT NULL,
    codigo_producto INT,
    categoria VARCHAR(50),
    motivo VARCHAR(100),

    CONSTRAINT id_plan_orden_filtro_plan_indx PRIMARY KEY NONCLUSTERED (id_plan, orden) ON [FG_Indices],
    CONSTRAINT chk_orden_filtro CHECK (orden > 0),
    CONSTRAINT chk_tipo_filtro CHECK (tipo_filtro IN ('producto', 'categoria', 'motivo')),
    CONSTRAINT chk_valor_filtro CHECK (
        (tipo_filtro = 'producto' AND codigo_producto IS NOT NULL AND categoria IS NULL AND motivo IS NULL)
        OR (tipo_filtro = 'categoria' AND categoria IS NOT NULL AND codigo_producto IS NULL AND motivo IS NULL)
        OR (tipo_filtro = 'motivo' AND motivo IS NOT NULL AND codigo_producto IS NULL AND categoria IS NULL)),
    CONSTRAINT fk_filtro_plan FOREIGN KEY (id_plan) REFERENCES comisiones_schema.plan_comision(codigo) ON DELETE CASCADE,
    CONSTRAINT fk_filtro_producto FOREIGN KEY (codigo_producto) REFERENCES comisiones_schema.producto(codigo)
) ON [FG_Tablas];
GO

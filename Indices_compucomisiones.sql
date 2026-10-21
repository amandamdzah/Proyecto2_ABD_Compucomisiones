USE COMPUCOMISIONES
GO

CREATE NONCLUSTERED INDEX nombre_persona_indx 
ON comisiones_schema.persona(nombre) ON [FG_Indices];

CREATE NONCLUSTERED INDEX nombre_cliente_indx 
ON comisiones_schema.cliente(nombre) ON [FG_Indices];

CREATE NONCLUSTERED INDEX nombre_producto_indx 
ON comisiones_schema.producto(nombre) ON [FG_Indices];

CREATE NONCLUSTERED INDEX nombre_rol_venta_indx 
ON comisiones_schema.rol_venta(nombre) ON [FG_Indices];

CREATE NONCLUSTERED INDEX nombre_plan_comision_indx 
ON comisiones_schema.plan_comision(nombre) ON [FG_Indices];
GO
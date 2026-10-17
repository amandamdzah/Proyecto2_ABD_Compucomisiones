USE COMPUCOMISIONES
GO

CREATE NONCLUSTERED INDEX nombre_persona_indx 
ON persona(nombre) ON [FG_Indices];

CREATE NONCLUSTERED INDEX nombre_cliente_indx 
ON cliente(nombre) ON [FG_Indices];

CREATE NONCLUSTERED INDEX nombre_producto_indx 
ON producto(nombre) ON [FG_Indices];

CREATE NONCLUSTERED INDEX nombre_rol_venta_indx 
ON rol_venta(nombre) ON [FG_Indices];

CREATE NONCLUSTERED INDEX nombre_plan_comision_indx 
ON plan_comision(nombre) ON [FG_Indices];
GO
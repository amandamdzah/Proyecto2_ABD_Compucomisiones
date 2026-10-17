USE COMPUCOMISIONES;
GO

CREATE TABLE persona (
    id_persona INT NOT NULL,
    nombre VARCHAR(50) NOT NULL,
    apellidos VARCHAR(50) NOT NULL,
    correo VARCHAR(50) NOT NULL,
    creado_en DATETIMEOFFSET NOT NULL,
    estado BIT NOT NULL, -- (1 Activo, 0 inactivo)
    tipo_rol VARCHAR(15) NOT NULL,

    CONSTRAINT id_persona_persona_indx PRIMARY KEY NONCLUSTERED (id_persona) ON [FG_Indices],
    CONSTRAINT chk_tipo_rol CHECK (tipo_rol IN ('Vendedor', 'Supervisor', 'Finanzas'))
) ON [FG_Tablas];

CREATE TABLE finanzas (
    id_finanzas INT NOT NULL,
    cargo VARCHAR(20) NOT NULL,

    CONSTRAINT id_finanzas_finanzas_indx PRIMARY KEY NONCLUSTERED (id_finanzas) ON [FG_Indices],
    CONSTRAINT fk_finanzas_persona FOREIGN KEY (id_finanzas) REFERENCES persona(id_persona)
) ON [FG_Tablas];

CREATE TABLE vendedor (
    id_vendedor INT NOT NULL,
    cuota_ventas DECIMAL(10,2) NOT NULL,
    
    CONSTRAINT id_vendedor_vendedor_indx PRIMARY KEY NONCLUSTERED (id_vendedor) ON [FG_Indices],
    CONSTRAINT fk_vendedor_persona FOREIGN KEY (id_vendedor) REFERENCES persona(id_persona)
) ON [FG_Tablas];

CREATE TABLE supervisor (
    id_supervisor INT NOT NULL, 
    zona VARCHAR(50) NOT NULL,
    id_supervisor_jefe INT,
    
    CONSTRAINT id_supervisor_supervisor_indx PRIMARY KEY NONCLUSTERED (id_supervisor) ON [FG_Indices],
    CONSTRAINT fk_supervisor_persona FOREIGN KEY (id_supervisor) REFERENCES persona(id_persona),
    CONSTRAINT fk_jefe FOREIGN KEY (id_supervisor_jefe) REFERENCES supervisor(id_supervisor)
) ON [FG_Tablas];

CREATE TABLE historial_asignacion (
    id_vendedor INT NOT NULL,
    fecha_desde DATE NOT NULL,
    id_supervisor INT NOT NULL,
    fecha_hasta DATE,
    porcentaje_reconocimiento DECIMAL(5,2) NOT NULL,
    
    CONSTRAINT id_vendedor_fecha_desde_historial_asignacion_indx PRIMARY KEY NONCLUSTERED (id_vendedor, fecha_desde) ON [FG_Indices],
    CONSTRAINT fk_historial_vendedor FOREIGN KEY (id_vendedor) REFERENCES vendedor(id_vendedor),
    CONSTRAINT fk_historial_supervisor FOREIGN KEY (id_supervisor) REFERENCES supervisor(id_supervisor)
) ON [FG_Tablas];

CREATE TABLE cliente (
    codigo INT NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    segmento VARCHAR(50) NOT NULL,

    CONSTRAINT codigo_cliente_indx PRIMARY KEY NONCLUSTERED (codigo) ON [FG_Indices]
) ON [FG_Tablas];

CREATE TABLE producto (
    codigo INT NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    categoria VARCHAR(50) NOT NULL,

    CONSTRAINT codigo_producto_indx PRIMARY KEY NONCLUSTERED (codigo) ON [FG_Indices]
) ON [FG_Tablas];

CREATE TABLE rol_venta (
    id_rol INT NOT NULL,
    nombre VARCHAR(50) NOT NULL,
    descripcion VARCHAR(200),

    CONSTRAINT id_rol_rol_venta_indx PRIMARY KEY NONCLUSTERED (id_rol) ON [FG_Indices]
) ON [FG_Tablas];

CREATE TABLE factura (
    numero INT NOT NULL,
    fecha_emision DATETIMEOFFSET NOT NULL,
    situacion VARCHAR(20) NOT NULL,
    fecha_cobro DATETIMEOFFSET,
    codigo_cliente INT NOT NULL,

    CONSTRAINT numero_factura_indx PRIMARY KEY NONCLUSTERED (numero) ON [FG_Indices],
    CONSTRAINT chk_situacion CHECK (situacion IN ('recien emitida', 'cobrada', 'anulada')),
    CONSTRAINT fk_factura_cliente FOREIGN KEY (codigo_cliente) REFERENCES cliente(codigo)
) ON [FG_Tablas];

CREATE TABLE detalle_factura (
    numero_factura INT NOT NULL,
    codigo_producto INT NOT NULL,
    cantidad INT NOT NULL,
    monto DECIMAL(12,2) NOT NULL,
    motivo VARCHAR(100) NOT NULL,
    
    CONSTRAINT numero_factura_codigo_producto_detalle_factura_indx PRIMARY KEY NONCLUSTERED (numero_factura, codigo_producto) ON [FG_Indices],
    CONSTRAINT fk_detalle_factura FOREIGN KEY (numero_factura) REFERENCES factura(numero),
    CONSTRAINT fk_detalle_producto FOREIGN KEY (codigo_producto) REFERENCES producto(codigo)
) ON [FG_Tablas];

CREATE TABLE participacion_factura (
    numero_factura INT NOT NULL,
    id_vendedor INT NOT NULL,
    id_rol INT NOT NULL,
    porcentaje DECIMAL(5,2) NOT NULL,
    
    CONSTRAINT numero_factura_id_vendedor_id_rol_participacion_factura_indx PRIMARY KEY NONCLUSTERED (numero_factura, id_vendedor, id_rol) ON [FG_Indices],
    CONSTRAINT fk_participacion_factura FOREIGN KEY (numero_factura) REFERENCES factura(numero),
    CONSTRAINT fk_participacion_vendedor FOREIGN KEY (id_vendedor) REFERENCES vendedor(id_vendedor),
    CONSTRAINT fk_participacion_rol FOREIGN KEY (id_rol) REFERENCES rol_venta(id_rol)
) ON [FG_Tablas];

CREATE TABLE plan_comision (
    codigo INT NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    tasa DECIMAL(5,2) NOT NULL,
    base VARCHAR(20) NOT NULL,
    admite_descuentos BIT NOT NULL, -- (1 admite retraer la comisión, 0 si no)
    
    CONSTRAINT codigo_plan_comision_indx PRIMARY KEY NONCLUSTERED (codigo) ON [FG_Indices],
    CONSTRAINT chk_base_plan CHECK (base IN ('ingreso', 'margen', 'cantidad'))
) ON [FG_Tablas];

CREATE TABLE asignacion_plan_vendedor (
    id_vendedor INT NOT NULL,
    id_rol INT NOT NULL,
    fecha_desde DATE NOT NULL,
    id_plan INT NOT NULL,
    -- Capaz se puede agregar fecha_hasta
    
    CONSTRAINT id_vendedor_id_rol_fecha_desde_asignacion_plan_vendedor_indx PRIMARY KEY NONCLUSTERED (id_vendedor, id_rol, fecha_desde) ON [FG_Indices],
    CONSTRAINT fk_asignacion_vendedor FOREIGN KEY (id_vendedor) REFERENCES vendedor(id_vendedor),
    CONSTRAINT fk_asignacion_rol FOREIGN KEY (id_rol) REFERENCES rol_venta(id_rol),
    CONSTRAINT fk_asignacion_plan FOREIGN KEY (id_plan) REFERENCES plan_comision(codigo)
) ON [FG_Tablas];

CREATE TABLE periodo (
    id_periodo INT NOT NULL,
    descripcion VARCHAR(100) NOT NULL,
    notas VARCHAR(500),
    tipo_periodo VARCHAR(15) NOT NULL,
    fecha_inicio DATE NOT NULL,
    fecha_cierre DATE NOT NULL,
    
    CONSTRAINT id_periodo_periodo_indx PRIMARY KEY NONCLUSTERED (id_periodo) ON [FG_Indices],
    CONSTRAINT chk_tipo_periodo CHECK (tipo_periodo IN ('semanal', 'mensual', 'trimestral', 'anual')),
    CONSTRAINT chk_fechas_logicas CHECK (fecha_cierre >= fecha_inicio)
) ON [FG_Tablas];

CREATE TABLE calculo_comision (
    id_periodo INT NOT NULL,
    id_persona INT NOT NULL,
    monto_ventas_propias DECIMAL(12,2) NOT NULL DEFAULT 0,
    monto_supervision DECIMAL(12,2) NOT NULL DEFAULT 0,
    estado VARCHAR(20) NOT NULL,
    
    CONSTRAINT id_periodo_id_persona_calculo_comision_indx PRIMARY KEY NONCLUSTERED (id_periodo, id_persona) ON [FG_Indices],
    CONSTRAINT fk_calculo_periodo FOREIGN KEY (id_periodo) REFERENCES periodo(id_periodo),
    CONSTRAINT fk_calculo_persona FOREIGN KEY (id_persona) REFERENCES persona(id_persona)
) ON [FG_Tablas];

CREATE TABLE pago (
    id_pago INT NOT NULL,
    id_periodo INT NOT NULL,
    id_persona INT NOT NULL,
    fecha DATE NOT NULL,
    monto DECIMAL(12,2) NOT NULL,
    estado VARCHAR (20) NOT NULL,

    CONSTRAINT id_pago_pago_indx PRIMARY KEY NONCLUSTERED (id_pago) ON [FG_Indices],
    CONSTRAINT fk_pago_periodo FOREIGN KEY (id_periodo) REFERENCES periodo(id_periodo),
    CONSTRAINT fk_pago_persona FOREIGN KEY (id_persona) REFERENCES persona(id_persona)
) ON [FG_Tablas];
GO

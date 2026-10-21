USE COMPUCOMISIONES;
GO

ALTER TABLE comisiones_schema.persona ADD CONSTRAINT uq_correo_persona UNIQUE (correo) ON [FG_Indices];
ALTER TABLE comisiones_schema.persona ADD CONSTRAINT chk_correo_persona CHECK (correo LIKE '%_@_%._%');
GO

-- cada persona en una sola funcion
ALTER TABLE comisiones_schema.persona ADD CONSTRAINT uq_id_tipo_persona UNIQUE (id_persona, tipo_rol) ON [FG_Indices];

ALTER TABLE comisiones_schema.vendedor ADD tipo_rol VARCHAR(15) NOT NULL DEFAULT 'Vendedor';
ALTER TABLE comisiones_schema.supervisor ADD tipo_rol VARCHAR(15) NOT NULL DEFAULT 'Supervisor';
ALTER TABLE comisiones_schema.finanzas ADD tipo_rol VARCHAR(15) NOT NULL DEFAULT 'Finanzas';
GO

ALTER TABLE comisiones_schema.vendedor ADD CONSTRAINT chk_tipo_vendedor CHECK (tipo_rol = 'Vendedor');
ALTER TABLE comisiones_schema.supervisor ADD CONSTRAINT chk_tipo_supervisor CHECK (tipo_rol = 'Supervisor');
ALTER TABLE comisiones_schema.finanzas ADD CONSTRAINT chk_tipo_finanzas CHECK (tipo_rol = 'Finanzas');

ALTER TABLE comisiones_schema.vendedor ADD CONSTRAINT fk_vendedor_tipo FOREIGN KEY (id_vendedor, tipo_rol) REFERENCES comisiones_schema.persona(id_persona, tipo_rol);
ALTER TABLE comisiones_schema.supervisor ADD CONSTRAINT fk_supervisor_tipo FOREIGN KEY (id_supervisor, tipo_rol) REFERENCES comisiones_schema.persona(id_persona, tipo_rol);
ALTER TABLE comisiones_schema.finanzas ADD CONSTRAINT fk_finanzas_tipo FOREIGN KEY (id_finanzas, tipo_rol) REFERENCES comisiones_schema.persona(id_persona, tipo_rol);
GO

ALTER TABLE comisiones_schema.participacion_factura ADD CONSTRAINT chk_porcentaje_participacion CHECK (porcentaje > 0 AND porcentaje <= 100);
ALTER TABLE comisiones_schema.plan_comision ADD CONSTRAINT chk_tasa_plan CHECK (tasa >= 0 AND tasa <= 100);
ALTER TABLE comisiones_schema.historial_asignacion ADD CONSTRAINT chk_porcentaje_historial CHECK (porcentaje_reconocimiento >= 0 AND porcentaje_reconocimiento <= 100);
GO

ALTER TABLE comisiones_schema.vendedor ADD CONSTRAINT chk_cuota_vendedor CHECK (cuota_ventas >= 0);
ALTER TABLE comisiones_schema.detalle_factura ADD CONSTRAINT chk_montos_detalle CHECK (cantidad > 0 AND monto >= 0 AND costo >= 0);
ALTER TABLE comisiones_schema.calculo_comision ADD CONSTRAINT chk_montos_calculo CHECK (monto_ventas_propias >= 0 AND monto_supervision >= 0);
ALTER TABLE comisiones_schema.pago ADD CONSTRAINT chk_monto_pago CHECK (monto >= 0);
GO

ALTER TABLE comisiones_schema.calculo_comision ADD CONSTRAINT chk_estado_calculo CHECK (estado IN ('calculado', 'pagado', 'retenido'));
ALTER TABLE comisiones_schema.pago ADD CONSTRAINT chk_estado_pago CHECK (estado IN ('pendiente', 'pagado', 'retenido'));
GO

ALTER TABLE comisiones_schema.factura ADD CONSTRAINT chk_fecha_cobro CHECK (fecha_cobro IS NULL OR fecha_cobro >= fecha_emision);
ALTER TABLE comisiones_schema.factura ADD CONSTRAINT chk_cobro_situacion CHECK (
    (situacion = 'recien emitida' AND fecha_cobro IS NULL)
    OR (situacion = 'cobrada' AND fecha_cobro IS NOT NULL)
    OR situacion = 'anulada');
GO

ALTER TABLE comisiones_schema.historial_asignacion ADD CONSTRAINT chk_fechas_historial CHECK (fecha_hasta IS NULL OR fecha_hasta >= fecha_desde);
GO

ALTER TABLE comisiones_schema.periodo ADD CONSTRAINT chk_duracion_periodo CHECK (
    (tipo_periodo = 'semanal' AND fecha_cierre = DATEADD(DAY, 6, fecha_inicio))
    OR (tipo_periodo = 'mensual' AND fecha_cierre = DATEADD(DAY, -1, DATEADD(MONTH, 1, fecha_inicio)))
    OR (tipo_periodo = 'trimestral' AND fecha_cierre = DATEADD(DAY, -1, DATEADD(MONTH, 3, fecha_inicio)))
    OR (tipo_periodo = 'anual' AND fecha_cierre = DATEADD(DAY, -1, DATEADD(YEAR, 1, fecha_inicio))));
GO

USE COMPUCOMISIONES;
GO

CREATE OR ALTER VIEW vw_reporte_pagos AS
SELECT 
    p.id_pago,
    p.fecha AS fecha_pago,
    p.monto AS monto_pago,
    p.estado AS estado_pago,
    per_reporte.id_periodo AS id_periodo_reporte,
    per_reporte.descripcion AS descripcion_periodo_reporte,
    per_reporte.tipo_periodo,
    per_reporte.fecha_inicio AS inicio_periodo_reporte,
    per_reporte.fecha_cierre AS cierre_periodo_reporte,
    p.id_periodo AS id_periodo_calculo,
    pers.id_persona,
    pers.nombre AS nombre_persona,
    pers.apellidos AS apellidos_persona,
    pers.correo AS correo_persona,
    pers.tipo_rol
FROM pago p
INNER JOIN persona pers ON p.id_persona = pers.id_persona
INNER JOIN periodo per_reporte ON p.fecha BETWEEN per_reporte.fecha_inicio AND per_reporte.fecha_cierre;
GO
--prueba para perio do mensual
SELECT * FROM vw_reporte_pagos WHERE tipo_periodo = 'mensual';

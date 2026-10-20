USE COMPUCOMISIONES;
GO

CREATE VIEW vw_reporte_pagos AS
SELECT 
    p.id_pago,
    p.fecha AS fecha_pago,
    p.monto AS monto_pago,
    p.estado AS estado_pago,
    
    
    per.id_periodo,
    per.descripcion AS descripcion_periodo,
    per.tipo_periodo,
    per.fecha_inicio AS inicio_periodo,
    per.fecha_cierre AS cierre_periodo,
    
    pers.id_persona,
    pers.nombre AS nombre_persona,
    pers.apellidos AS apellidos_persona,
    pers.correo AS correo_persona,
    pers.tipo_rol
FROM pago p
INNER JOIN periodo per ON p.id_periodo = per.id_periodo
INNER JOIN persona pers ON p.id_persona = pers.id_persona;
GO

--prueba para perio do mensual
SELECT * FROM vw_reporte_pagos WHERE tipo_periodo = 'mensual';


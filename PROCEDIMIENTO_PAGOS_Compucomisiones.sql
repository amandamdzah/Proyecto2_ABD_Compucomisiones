USE COMPUCOMISIONES;
GO

CREATE OR ALTER PROCEDURE sp_registrar_pagos
    @id_periodo_pago INT,
    @id_periodo_calculo INT,
    @fecha_pago DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @inicio DATE, @cierre DATE, @ultimo_id INT;

    -- fechas del periodo de pago
    SELECT @inicio = fecha_inicio, @cierre = fecha_cierre
    FROM periodo
    WHERE id_periodo = @id_periodo_pago;

    IF @inicio IS NULL
    BEGIN
        RAISERROR ('El periodo de pago no existe.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM calculo_comision WHERE id_periodo = @id_periodo_calculo)
    BEGIN
        RAISERROR ('No hay un cálculo de comisiones registrado para ese periodo.', 16, 1);
        RETURN;
    END

    -- si no mandan fecha se usa el cierre
    IF @fecha_pago IS NULL
        SET @fecha_pago = @cierre;

    IF @fecha_pago < @inicio OR @fecha_pago > @cierre
    BEGIN
        RAISERROR ('La fecha de pago tiene que estar dentro del periodo de pago.', 16, 1);
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        -- ultimo id para seguir la numeracion
        SELECT @ultimo_id = ISNULL(MAX(id_pago), 0) FROM pago;

        -- un pago por persona con comision
        INSERT INTO pago (id_pago, id_periodo, id_persona, fecha, monto, estado)
        SELECT
            @ultimo_id + ROW_NUMBER() OVER (ORDER BY cc.id_persona),
            @id_periodo_pago,
            cc.id_persona,
            @fecha_pago,
            cc.monto_ventas_propias + cc.monto_supervision,
            'pendiente'
        FROM calculo_comision AS cc
        WHERE cc.id_periodo = @id_periodo_calculo
          AND cc.estado = 'calculado'
          AND cc.monto_ventas_propias + cc.monto_supervision > 0;

        -- activos pagado, inactivos retenido
        UPDATE pg
        SET pg.estado = CASE WHEN p.estado = 1 THEN 'pagado' ELSE 'retenido' END
        FROM pago AS pg
        INNER JOIN persona AS p ON pg.id_persona = p.id_persona
        WHERE pg.id_periodo = @id_periodo_pago
          AND pg.estado = 'pendiente';

        -- retenidos que ya estan activos
        UPDATE pg
        SET pg.estado = 'pagado'
        FROM pago AS pg
        INNER JOIN persona AS p ON pg.id_persona = p.id_persona
        WHERE pg.id_periodo = @id_periodo_pago
          AND pg.estado = 'retenido'
          AND p.estado = 1;

        -- el calculo queda igual que su pago
        UPDATE cc
        SET cc.estado = pg.estado
        FROM calculo_comision AS cc
        INNER JOIN pago AS pg ON cc.id_persona = pg.id_persona
        WHERE cc.id_periodo = @id_periodo_calculo
          AND pg.id_periodo = @id_periodo_pago
          AND cc.estado IN ('calculado', 'retenido');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    -- pagos del periodo
    SELECT pg.id_pago, p.nombre, p.apellidos, pg.fecha, pg.monto, pg.estado
    FROM pago AS pg
    INNER JOIN persona AS p ON pg.id_persona = p.id_persona
    WHERE pg.id_periodo = @id_periodo_pago
    ORDER BY pg.id_pago;
END;
GO

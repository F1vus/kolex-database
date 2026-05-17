CREATE OR REPLACE FUNCTION backend.get_user_tickets(
    p_email VARCHAR
)
RETURNS TABLE (
    ticket_id BIGINT,
    departure_date TIMESTAMP,
    ticket_price NUMERIC,
    ticket_status VARCHAR
)
AS $$
BEGIN
RETURN QUERY
SELECT
    t.ticket_id,
    t.departure_date,
    t.ticket_price,
    t.ticket_status
FROM backend.ticket t
         JOIN backend.profile p ON t.profile_id = p.profile_id
         JOIN backend.user u ON p.user_id = u.user_id
WHERE u.user_email = p_email;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION backend.get_user_tickets(VARCHAR) IS
'Zwraca wszystkie bilety przypisane do użytkownika na podstawie emaila.';


CREATE OR REPLACE FUNCTION backend.get_travels_by_train(
    p_train VARCHAR
)
RETURNS TABLE (
    travel_id BIGINT,
    travel_departure TIMESTAMP,
    travel_duration INTERVAL,
    travel_train VARCHAR
)
AS $$
BEGIN
RETURN QUERY
SELECT
    travel_id,
    travel_departure,
    travel_duration,
    travel_train
FROM backend.travel
WHERE travel_train = p_train;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION backend.get_travels_by_train(VARCHAR) IS
'Zwraca wszystkie podróże dla wybranego pociągu.';


CREATE OR REPLACE FUNCTION backend.reserve_seat(
    p_seat_id BIGINT,
    p_profile_id BIGINT,
    p_start_stop INT,
    p_end_stop INT
)
RETURNS TABLE (
    reservation_id BIGINT,
    seat_id BIGINT,
    status VARCHAR,
    created_at TIMESTAMP,
    expires_at TIMESTAMP
)
AS $$
BEGIN
    -- sprawdzenie konfliktu
    IF EXISTS (
        SELECT 1
        FROM backend.seat_reservation sr
        WHERE sr.seat_id = p_seat_id
          AND sr.status = 'HELD'
          AND sr.expires_at > NOW()
    ) THEN
        RAISE EXCEPTION 'Seat is already reserved';
    END IF;

    RETURN QUERY
    INSERT INTO backend.seat_reservation AS sr (
        seat_id,
        profile_id,
        status,
        start_stop_number,
        end_stop_number,
        created_at,
        expires_at
    )
    VALUES (
        p_seat_id,
        p_profile_id,
        'HELD',
        p_start_stop,
        p_end_stop,
        NOW(),
        NOW() + INTERVAL '10 minutes'
    )
    RETURNING
        sr.reservation_id,
        sr.seat_id,
        sr.status,
        sr.created_at,
        sr.expires_at;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION backend.buy_ticket(
    p_reservation_id BIGINT,
    p_user_id BIGINT
)
RETURNS TABLE (
    ticket_id BIGINT,
    message TEXT
)
AS $$
DECLARE
    v_res backend.seat_reservation%ROWTYPE;
    v_user_balance NUMERIC;
    v_total_price NUMERIC;
    v_ticket_id BIGINT;
    v_travel_departure TIMESTAMP;
    v_offset INTERVAL;
BEGIN

    -- =========================================================
    -- 1. LOAD RESERVATION
    -- =========================================================
    SELECT *
    INTO v_res
    FROM backend.seat_reservation sr
    WHERE sr.reservation_id = p_reservation_id
    FOR UPDATE;

    IF v_res IS NULL THEN
        RAISE EXCEPTION 'No reservation found';
    END IF;

    IF v_res.status <> 'HELD' THEN
        RAISE EXCEPTION 'Reservation already processed';
    END IF;

    IF v_res.expires_at < NOW() THEN
        RAISE EXCEPTION 'Reservation expired';
    END IF;

    -- =========================================================
    -- 2. CALCULATE PRICE (simplified equivalent of calculatePrice)
    -- =========================================================
    v_total_price :=
        (v_res.end_stop_number - v_res.start_stop_number) * 10;

    -- =========================================================
    -- 3. CHECK USER BALANCE
    -- =========================================================
    SELECT user_balance
    INTO v_user_balance
    FROM backend."user"
    WHERE user_id = p_user_id
    FOR UPDATE;

    IF v_user_balance IS NULL THEN
        RAISE EXCEPTION 'User not found';
    END IF;

    IF v_user_balance < v_total_price THEN
        RAISE EXCEPTION 'Insufficient funds';
    END IF;

    -- =========================================================
    -- 4. DEDUCT BALANCE
    -- =========================================================
    UPDATE backend."user"
    SET user_balance = user_balance - v_total_price
    WHERE user_id = p_user_id;

    -- =========================================================
    -- 5. GET TRAVEL DATA (departure + offset logic)
    -- =========================================================
    SELECT t.travel_departure
    INTO v_travel_departure
    FROM backend.travel t
    JOIN backend.seat s ON s.travel_id = t.travel_id
    WHERE s.seat_id = v_res.seat_id;

    SELECT tr.departure_offset
    INTO v_offset
    FROM backend.travel_route tr
    WHERE tr.travel_id = (
        SELECT travel_id FROM backend.seat WHERE seat_id = v_res.seat_id
    )
    AND tr.travel_stop_number = v_res.start_stop_number;

    -- =========================================================
    -- 6. CREATE TICKET
    -- =========================================================
    INSERT INTO backend.ticket as t (
        travel_id,
        profile_id,
        ticket_price,
        departure_date,
        start_stop_number,
        end_stop_number,
        ticket_created_at,
        seat_id,
        ticket_status
    )
    VALUES (
        (SELECT travel_id FROM backend.seat WHERE seat_id = v_res.seat_id),
        v_res.profile_id,
        v_total_price,
        v_travel_departure + v_offset,
        v_res.start_stop_number,
        v_res.end_stop_number,
        NOW(),
        v_res.seat_id,
        'PAID'
    )
    RETURNING t.ticket_id INTO v_ticket_id;

    -- =========================================================
    -- 7. FINALIZE RESERVATION
    -- =========================================================
    UPDATE backend.seat_reservation
    SET status = 'PURCHASED',
        ticket_id = v_ticket_id
    WHERE reservation_id = p_reservation_id;

    -- =========================================================
    -- RETURN
    -- =========================================================
    RETURN QUERY
    SELECT v_ticket_id, 'Ticket purchased successfully';

END;
$$ LANGUAGE plpgsql;

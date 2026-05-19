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


        CREATE OR REPLACE FUNCTION backend.get_seat_reservations(
    p_seat_id BIGINT
)
RETURNS TABLE (
    reservation_id BIGINT,
    profile_id BIGINT,
    status VARCHAR,
    start_stop_number INT,
    end_stop_number INT,
    created_at TIMESTAMP,
    expires_at TIMESTAMP
)
AS $$
BEGIN
RETURN QUERY
SELECT
    sr.reservation_id,
    sr.profile_id,
    sr.status,
    sr.start_stop_number,
    sr.end_stop_number,
    sr.created_at,
    sr.expires_at
FROM backend.seat_reservation sr
WHERE sr.seat_id = p_seat_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION backend.get_seat_reservations(BIGINT) IS
'Zwraca wszystkie rezerwacje dla konkretnego miejsca (seat).';


CREATE OR REPLACE FUNCTION backend.get_user_balance(
    p_email VARCHAR
)
RETURNS NUMERIC
AS $$
DECLARE
v_balance NUMERIC;
BEGIN
SELECT u.user_balance
INTO v_balance
FROM backend.user u
WHERE u.user_email = p_email;

RETURN v_balance;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION backend.get_user_balance(VARCHAR) IS
'Zwraca aktualne saldo użytkownika na podstawie emaila.';
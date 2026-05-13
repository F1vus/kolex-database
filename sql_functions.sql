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
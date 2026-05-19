-- ============================================
-- ZAPYTANIA ZŁOŻONE - PROJEKT KOLEO
-- PostgreSQL
-- ============================================


-- ============================================
-- QUERY 1
-- Agregacja + JOIN
-- Statystyki sprzedaży biletów
-- ============================================

SELECT
    tr.travel_id,
    tr.travel_train,
    COUNT(t.ticket_id) AS sold_tickets,
    SUM(t.ticket_price) AS total_revenue,
    AVG(t.ticket_price) AS average_ticket_price
FROM backend.travel tr
         JOIN backend.ticket t
              ON tr.travel_id = t.travel_id
GROUP BY tr.travel_id, tr.travel_train
ORDER BY total_revenue DESC;



-- ============================================
-- QUERY 2
-- JOIN wielu tabel
-- Historia zakupów użytkowników
-- ============================================

SELECT
    u.user_email,
    p.profile_first_name,
    p.profile_last_name,
    tr.travel_train,
    t.ticket_price,
    t.departure_date
FROM backend."user" u
         JOIN backend.profile p
              ON u.user_id = p.user_id
         JOIN backend.ticket t
              ON p.profile_id = t.profile_id
         JOIN backend.travel tr
              ON t.travel_id = tr.travel_id
ORDER BY t.departure_date;



-- ============================================
-- QUERY 3
-- Podzapytanie
-- Użytkownicy wydający więcej niż średnia
-- ============================================

SELECT
    p.profile_first_name,
    p.profile_last_name,
    SUM(t.ticket_price) AS total_spent
FROM backend.profile p
         JOIN backend.ticket t
              ON p.profile_id = t.profile_id
GROUP BY
    p.profile_id,
    p.profile_first_name,
    p.profile_last_name
HAVING SUM(t.ticket_price) > (
    SELECT AVG(user_total)
    FROM (
             SELECT SUM(ticket_price) AS user_total
             FROM backend.ticket
             GROUP BY profile_id
         ) sub
)
ORDER BY total_spent DESC;

INSERT INTO backend.ticket (
    departure_date,
    ticket_price,
    travel_id,
    profile_id,
    start_stop_number,
    end_stop_number,
    ticket_created_at,
    ticket_status
)
VALUES (
           NOW(),
           59.90,
           47,
           1,
           1,
           2,
           NOW(),
           'PAID'
       );

-- ============================================
-- QUERY 4
-- CTE (WITH)
-- Ranking najpopularniejszych stacji
-- ============================================

WITH station_stats AS (

    SELECT
        s.station_name,
        COUNT(tr.travel_id) AS total_travels
    FROM backend.station s
             JOIN backend.travel_route tr
                  ON s.station_id = tr.travel_station_stop_id
    GROUP BY s.station_name

)

SELECT
    station_name,
    total_travels
FROM station_stats
ORDER BY total_travels DESC;



-- ============================================
-- QUERY 5
-- LEFT JOIN + agregacja
-- Obłożenie miejsc w pociągach
-- ============================================

SELECT
    tr.travel_train,
    COUNT(s.seat_id) AS total_seats,
    COUNT(sr.reservation_id) AS reserved_seats
FROM backend.travel tr
         JOIN backend.seat s
              ON tr.travel_id = s.travel_id
         LEFT JOIN backend.seat_reservation sr
                   ON s.seat_id = sr.seat_id
GROUP BY tr.travel_train
ORDER BY reserved_seats DESC;



-- ============================================
-- QUERY 6
-- CTE + agregacja
-- Podsumowanie wydatków użytkowników
-- ============================================

WITH user_summary AS (

    SELECT
        profile_id,
        COUNT(ticket_id) AS tickets_count,
        SUM(ticket_price) AS total_spent
    FROM backend.ticket
    GROUP BY profile_id

)

SELECT
    p.profile_first_name,
    p.profile_last_name,
    us.tickets_count,
    us.total_spent
FROM user_summary us
         JOIN backend.profile p
              ON us.profile_id = p.profile_id
ORDER BY us.total_spent DESC;
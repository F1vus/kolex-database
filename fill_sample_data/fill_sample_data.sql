TRUNCATE backend.travel CASCADE;
TRUNCATE backend.travel_route CASCADE;
TRUNCATE backend.seat CASCADE;

CREATE EXTENSION IF NOT EXISTS pgcrypto;


-----------------------------------------------------------
CREATE OR REPLACE FUNCTION backend.fill_sample_data()
RETURNS boolean
LANGUAGE plpgsql
AS
$$
DECLARE
BEGIN
	--fill backned.travel
	INSERT INTO backend.travel (travel_departure, travel_duration, travel_train)
	SELECT
	    NOW() + (gs || ' hours')::interval,
	    (interval '1 hour' + ((random() * 180)::int || ' minutes')::interval),
	    CONCAT((ARRAY['IC 31', 'EIC ', 'EIP '])[1 + floor(random() * 3)::int], gs::text)
	FROM generate_series(1, 250) AS gs;

	--fill backend.travel_route
	WITH selected_stops AS (
	    SELECT
	        t.travel_id,
	        s.station_id,
	        row_number() OVER (PARTITION BY t.travel_id ORDER BY random()) AS stop_no
	    FROM backend.travel t
	    CROSS JOIN LATERAL (
	        SELECT station_id
	        FROM backend.station
	        ORDER BY random()
	        LIMIT 7
	    ) s
	)
	INSERT INTO backend.travel_route (
	    travel_id,
	    travel_station_stop_id,
	    travel_stop_number,
	    travel_distance,
	    travel_price,
	    arrival_offset,
	    departure_offset
	)
	SELECT
	    travel_id,
	    station_id,
	    stop_no,
	    (20 + floor(random() * 480))::int AS travel_distance,
	    round((20 + random() * 200)::numeric, 2) AS travel_price,
	    (stop_no - 1) * interval '15 minutes' AS arrival_offset,
	    (stop_no - 1) * interval '15 minutes' + interval '5 minutes' AS departure_offset
	FROM selected_stops
	ORDER BY travel_id, stop_no;

	-- file backend.seat
	INSERT INTO backend.seat (travel_id, seat_number)
	SELECT
	    t.travel_id,
	    s.seat_number
	FROM backend.travel t
	CROSS JOIN generate_series(1, 92) AS s(seat_number);
   
   RETURN TRUE;
END;
$$;


SELECT backend.fill_sample_data();


-----------------------------------------------------------
CREATE OR REPLACE FUNCTION backend.fill_sample_user_data()
RETURNS boolean
LANGUAGE plpgsql
AS
$$
DECLARE
BEGIN
	--fill backend.user
	INSERT INTO backend.user(user_password, user_email, user_created_at, user_role, user_balance, user_enabled)
	SELECT
    	crypt('password123', gen_salt('bf')),
	    CONCAT('jan_kowalski',gs::text,'@gmail.com'),
	    NOW() + (gs || ' hours')::interval,
		'USER',
		round((random() * 1000)::numeric, 2),
		TRUE
	FROM generate_series(1, 500) AS gs;

	--fill backend.user
	WITH user_profiles AS (
	    SELECT
	        u.user_id,
			(ARRAY['Jan', 'Anna', 'Wałerij'])[1 + floor(random() * 3)::int] AS profile_first_name,
			(ARRAY['Kowalski', 'Nowak', 'Kowal'])[1 + floor(random() * 3)::int] AS profile_last_name
	    FROM backend.user u
		UNION ALL
		SELECT
	        u.user_id,
			(ARRAY['Jan', 'Anna', 'Wałerij'])[1 + floor(random() * 3)::int] AS profile_first_name,
			(ARRAY['Kowalski', 'Nowak', 'Kowal'])[1 + floor(random() * 3)::int] AS profile_last_name
	    FROM backend.user u
		UNION ALL
		SELECT
	        u.user_id,
			(ARRAY['Jan', 'Anna', 'Wałerij'])[1 + floor(random() * 3)::int] AS profile_first_name,
			(ARRAY['Kowalski', 'Nowak', 'Kowal'])[1 + floor(random() * 3)::int] AS profile_last_name
	    FROM backend.user u
	)
	INSERT INTO backend.profile (
	    user_id,
	    profile_first_name,
	    profile_last_name,
	    profile_created_at
	)
	SELECT DISTINCT
	    user_id,
	    profile_first_name,
	    profile_last_name,
	   	NOW() + interval '1 hour' AS profile_created_at
	FROM user_profiles
	ORDER BY user_id;

   RETURN TRUE;
END;
$$;

SELECT backend.fill_sample_user_data();

-----------------------------------------------------------
CREATE OR REPLACE FUNCTION backend.generate_test_tickets()
RETURNS TABLE (
    profile_id BIGINT,
    reservation_id BIGINT,
    ticket_id BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
v_profile RECORD;
    v_travel_id BIGINT;
    v_seat_id BIGINT;
    v_start_stop INT;
    v_end_stop INT;
    v_max_stop INT;
    v_reservation_id BIGINT;
    v_ticket_id BIGINT;
BEGIN
    FOR v_profile IN
    SELECT p.profile_id, p.user_id
    FROM backend.profile p
    WHERE NOT EXISTS (
        SELECT 1
        FROM backend.ticket t
        WHERE t.profile_id = p.profile_id
    )
    ORDER BY p.profile_id
        LOOP
    SELECT t.travel_id, MAX(tr.travel_stop_number)
    INTO v_travel_id, v_max_stop
    FROM backend.travel t
             JOIN backend.travel_route tr ON tr.travel_id = t.travel_id
    WHERE EXISTS (
        SELECT 1
        FROM backend.seat s
        WHERE s.travel_id = t.travel_id
    )
    GROUP BY t.travel_id
    HAVING COUNT(DISTINCT tr.travel_stop_number) >= 2
    ORDER BY random()
        LIMIT 1;

    IF v_travel_id IS NULL OR v_max_stop IS NULL OR v_max_stop < 2 THEN
                CONTINUE;
    END IF;

    SELECT s.seat_id
    INTO v_seat_id
    FROM backend.seat s
    WHERE s.travel_id = v_travel_id
    ORDER BY random()
        LIMIT 1;

    IF v_seat_id IS NULL THEN
                CONTINUE;
    END IF;

    v_start_stop := 1 + floor(random() * (v_max_stop - 1))::int;
    v_end_stop := v_start_stop + 1 + floor(random() * (v_max_stop - v_start_stop))::int;

    BEGIN
        SELECT r.reservation_id
        INTO v_reservation_id
        FROM backend.reserve_seat(
                     v_seat_id,
                     v_profile.profile_id,
                     v_start_stop,
                     v_end_stop
        ) AS r;

        IF v_reservation_id IS NULL THEN
                        CONTINUE;
        END IF;

        SELECT b.ticket_id
        INTO v_ticket_id
        FROM backend.buy_ticket(
                     v_reservation_id,
                     v_profile.user_id
        ) AS b;

        IF v_ticket_id IS NULL THEN
                        CONTINUE;
        END IF;

        profile_id := v_profile.profile_id;
        reservation_id := v_reservation_id;
        ticket_id := v_ticket_id;
        RETURN NEXT;

    EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'Skip profile_id=%, error=%', v_profile.profile_id, SQLERRM;
            CONTINUE;
            END;
            END LOOP;

    RETURN;
END;
$$;

SELECT * FROM backend.generate_test_tickets();

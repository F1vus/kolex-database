TRUNCATE backend.travel CASCADE;
TRUNCATE backend.travel_route CASCADE;
TRUNCATE backend.seat CASCADE;

CREATE EXTENSION IF NOT EXISTS pgcrypto;


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

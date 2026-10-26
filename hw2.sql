-- ============================================================
-- Домашнее задание к лекции «Продвинутый SQL»
-- Школа Аналитиков · учебная база hh_school
-- Автор: Мельников Тимофей Валерьевич
-- ============================================================


-- ============================================================
-- БЛОК А. Качество и подготовка данных
-- ============================================================

-- ЗАДАНИЕ 1
-- 1. Аудит качества данных. Каждая строка результата это один тип проверки
WITH call_links AS (
    -- Звонки + данные отклика
    SELECT
        c.call_id, c.response_id, c.vacancy_id, c.employer_id, c.applicant_id,
        c.caller_role, c.status, c.call_duration, c.call_at, c.call_tags,
        r.created_at AS response_at,
        r.vacancy_id AS response_vacancy_id,
        r.resume_id  AS response_resume_id,
        v.employer_id AS vacancy_employer_id
    FROM calls AS c
    LEFT JOIN responses AS r ON r.response_id = c.response_id
    LEFT JOIN vacancies AS v ON v.vacancy_id = r.vacancy_id
),
message_links AS (
    -- Сообщения + данные отклика
    SELECT
        m.message_id, m.response_id, m.vacancy_id, m.employer_id, m.applicant_id,
        m.sent_at, m.message_text, m.message_meta,
        r.created_at AS response_at,
        r.vacancy_id AS response_vacancy_id,
        r.resume_id  AS response_resume_id,
        v.employer_id AS vacancy_employer_id
    FROM messages AS m
    LEFT JOIN responses AS r ON r.response_id = m.response_id
    LEFT JOIN vacancies AS v ON v.vacancy_id = r.vacancy_id
),
unlinked_calls AS (
    -- Кандидаты-отклики для звонков без response_id (по vacancy_id + applicant_id)
    SELECT c.call_id, c.call_at, r.created_at AS candidate_response_at
    FROM calls AS c
    JOIN responses AS r
        ON r.vacancy_id = c.vacancy_id
       AND r.resume_id = c.applicant_id
    WHERE c.response_id IS NULL
)
-- Проверки проблем
SELECT 'calls' AS source, 'нет response_id' AS problem,
       COUNT(*) AS rows_cnt, STRING_AGG(call_id::text, ', ' ORDER BY call_id) AS ids
FROM call_links WHERE response_id IS NULL
UNION ALL
SELECT 'calls', 'нет response_id, и найденный по vacancy_id + applicant_id отклик создан позже звонка',
       COUNT(*), STRING_AGG(call_id::text, ', ' ORDER BY call_id)
FROM unlinked_calls WHERE call_at < candidate_response_at
UNION ALL
SELECT 'calls', 'vacancy_id звонка не совпадает с вакансией отклика',
       COUNT(*), STRING_AGG(call_id::text, ', ' ORDER BY call_id)
FROM call_links WHERE response_id IS NOT NULL AND vacancy_id <> response_vacancy_id
UNION ALL
SELECT 'calls', 'employer_id звонка не совпадает с работодателем вакансии',
       COUNT(*), STRING_AGG(call_id::text, ', ' ORDER BY call_id)
FROM call_links WHERE response_id IS NOT NULL AND employer_id <> vacancy_employer_id
UNION ALL
SELECT 'calls', 'applicant_id звонка не совпадает с resume_id отклика',
       COUNT(*), STRING_AGG(call_id::text, ', ' ORDER BY call_id)
FROM call_links WHERE response_id IS NOT NULL AND applicant_id <> response_resume_id
UNION ALL
SELECT 'calls', 'звонок раньше отклика',
       COUNT(*), STRING_AGG(call_id::text, ', ' ORDER BY call_id)
FROM call_links WHERE response_id IS NOT NULL AND call_at < response_at
UNION ALL
SELECT 'calls', 'технический тег противоречит status',
       COUNT(*), STRING_AGG(call_id::text, ', ' ORDER BY call_id)
FROM call_links
WHERE NOT (
       (status = 'successful'   AND 'connected' = ANY(call_tags)
            AND NOT ('no_answer' = ANY(call_tags) OR 'technical_error' = ANY(call_tags)))
    OR (status = 'unsuccessful' AND 'no_answer' = ANY(call_tags)
            AND NOT ('connected' = ANY(call_tags) OR 'technical_error' = ANY(call_tags)))
    OR (status = 'error'        AND 'technical_error' = ANY(call_tags)
            AND NOT ('connected' = ANY(call_tags) OR 'no_answer' = ANY(call_tags)))
)
UNION ALL
SELECT 'calls', 'caller_role противоречит тегу inbound / outbound',
       COUNT(*), STRING_AGG(call_id::text, ', ' ORDER BY call_id)
FROM call_links
WHERE NOT (
       (caller_role = 'employer'  AND 'outbound' = ANY(call_tags))
    OR (caller_role = 'applicant' AND 'inbound'  = ANY(call_tags))
)
UNION ALL
SELECT 'calls', 'status и call_duration противоречат (successful без длительности или длительность у неуспешного)',
       COUNT(*), STRING_AGG(call_id::text, ', ' ORDER BY call_id)
FROM call_links
WHERE (status = 'successful' AND call_duration IS NULL)
   OR (status <> 'successful' AND call_duration IS NOT NULL)
UNION ALL
SELECT 'calls', 'дубль звонка (одинаковые отклик, время и роль)',
       COUNT(*), STRING_AGG(call_id::text, ', ' ORDER BY call_id)
FROM (
    -- Подсчет одинаковых звонков
    SELECT call_id,
           COUNT(*) OVER (PARTITION BY response_id, call_at, caller_role) AS dup_cnt
    FROM calls
    WHERE response_id IS NOT NULL
) AS d
WHERE dup_cnt > 1
UNION ALL
SELECT 'calls', 'call_duration IS NULL (разговора не было)',
       COUNT(*), STRING_AGG(call_id::text, ', ' ORDER BY call_id)
FROM call_links WHERE call_duration IS NULL
UNION ALL
SELECT 'messages', 'vacancy_id сообщения не совпадает с вакансией отклика',
       COUNT(*), STRING_AGG(message_id::text, ', ' ORDER BY message_id)
FROM message_links WHERE vacancy_id <> response_vacancy_id
UNION ALL
SELECT 'messages', 'employer_id сообщения не совпадает с работодателем вакансии',
       COUNT(*), STRING_AGG(message_id::text, ', ' ORDER BY message_id)
FROM message_links WHERE employer_id <> vacancy_employer_id
UNION ALL
SELECT 'messages', 'applicant_id сообщения не совпадает с resume_id отклика',
       COUNT(*), STRING_AGG(message_id::text, ', ' ORDER BY message_id)
FROM message_links WHERE applicant_id <> response_resume_id
UNION ALL
SELECT 'messages', 'сообщение раньше отклика',
       COUNT(*), STRING_AGG(message_id::text, ', ' ORDER BY message_id)
FROM message_links WHERE sent_at < response_at
UNION ALL
SELECT 'messages', 'в message_meta нет channel, is_read или attachments',
       COUNT(*), STRING_AGG(message_id::text, ', ' ORDER BY message_id)
FROM message_links
WHERE message_meta ->> 'channel' IS NULL
   OR message_meta ->> 'is_read' IS NULL
   OR message_meta -> 'attachments' IS NULL
UNION ALL
SELECT 'messages', 'пустой текст сообщения',
       COUNT(*), STRING_AGG(message_id::text, ', ' ORDER BY message_id)
FROM message_links WHERE message_text IS NULL OR TRIM(message_text) = ''
UNION ALL
SELECT 'messages', 'дубль сообщения (одинаковые отклик, время и отправитель)',
       COUNT(*), STRING_AGG(message_id::text, ', ' ORDER BY message_id)
FROM (
    -- Подсчет одинаковых сообщений
    SELECT message_id,
           COUNT(*) OVER (PARTITION BY response_id, sent_at, sender_role) AS dup_cnt
    FROM messages
) AS d
WHERE dup_cnt > 1;


-- ВЫВОД. Реальная проблема нашлась одна: 8 звонков без response_id (call_id 700244–700251).
-- Это существенно, т.к. непонятно по какому отклику звонили.
-- Восстановить связь попробовал по vacancy_id и applicant_id (resume_id): для каждого из 8 звонков 
-- находится ровно один отклик, но он создан позже звонка, то есть событие стояло бы раньше отклика.
-- Поэтому их нельзя считать за разговоры после конкретного отклика, из аналитического слоя их исключаем
-- (JOIN с responses по response_id их отсекает).

-- Вторая находка: call_duration IS NULL у 70 звонков (69 недозвонов со статусом
-- unsuccessful и 1 звонок со статусом error, call_id в колонке ids).
-- Но эта проблема обьяснима: разговора просто не было. Она ломает только атрибут «длительность»,
-- но факт что работодатель звонил остается, поэтому такие звонки оставим.

-- Остальные проверки дали 0 строк: идентификаторы vacancy_id, employer_id и applicant_id в
-- звонках и сообщениях согласованы с откликом и вакансией, событий раньше отклика нет,
-- технические теги (connected / no_answer / technical_error) и направление (inbound / outbound)
-- согласуются со status и caller_role, дублей нет, в message_meta есть все три ключа, пустого
-- текста сообщений нет.


-- ОТДЕЛЬНО: Длительность состоявшихся звонков (где status = 'successful', длительность заполнена)
WITH successful_calls AS (
    -- Успешные звонки с длительностью
    SELECT call_id, call_duration
    FROM calls
    WHERE status = 'successful'
      AND call_duration IS NOT NULL
),
p99 AS (
    -- 99 перцентиль длительности
    SELECT PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY call_duration) AS p99_value
    FROM successful_calls
)
-- Итог
SELECT
    COUNT(*)                                                     AS calls_cnt,
    ROUND(AVG(sc.call_duration), 1)                              AS avg_duration,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY sc.call_duration) AS median_duration,
    p.p99_value                                                  AS p99_duration,
    COUNT(*) FILTER (WHERE sc.call_duration > p.p99_value)       AS calls_above_p99,
    ROUND(AVG(sc.call_duration) FILTER (WHERE sc.call_duration <= p.p99_value), 1) AS avg_without_above_p99
FROM successful_calls AS sc
CROSS JOIN p99 AS p
GROUP BY p.p99_value;

-- Звонки выше 99 перцентиля
SELECT call_id, call_duration
FROM calls
WHERE status = 'successful'
  AND call_duration > (
      SELECT PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY call_duration)
      FROM calls
      WHERE status = 'successful'
  )
ORDER BY call_duration DESC;


-- ВЫВОД. Состоявшихся звонков с длительностью всего 181. Средняя 467,3 с, медиана 438 с,
-- 99 перцентиль 890,4 с, выше него 2 звонка (700199 — 899 с и 700159 — 892 с), средняя без них 462,5 с.
-- Ошибками эти значения я не считаю: весь диапазон 51–899 с (899 с = 15 минут), нет ни
-- нулей, ни нереальных значений в часах, т.е. по сути это просто верхний край обычного
-- распределения (при 181 звонке 1%, а это как раз 2 звонка). Для типичной длительности
-- я бы взял медиану (438 с = 7,3 мин) т.к. она не зависит от хвоста.
-- Среднее после исключения этих значений почти не меняется (467,3 -> 462,5), исключать эти звонки не будем.


-- ============================================================
-- БЛОК Б. История коммуникаций
-- ============================================================

-- ЗАДАНИЕ 2
WITH messages_7d AS (
    -- Сообщения работодателя, 7 дней
    SELECT
        m.response_id,
        m.employer_id,
        m.message_id::text AS event_id,
        m.sent_at          AS event_at,
        'message'          AS event_type
    FROM messages AS m
    JOIN responses AS r
        ON r.response_id = m.response_id
    WHERE m.sender_role = 'employer'
      AND m.sent_at >= r.created_at
      AND m.sent_at <= r.created_at + INTERVAL '7 days'
),
calls_7d AS (
    -- Звонки работодателя, 7 дней (JOIN убирает звонки без response_id)
    SELECT
        c.response_id,
        c.employer_id,
        c.call_id::text AS event_id,
        c.call_at       AS event_at,
        'call'          AS event_type
    FROM calls AS c
    JOIN responses AS r
        ON r.response_id = c.response_id
    WHERE c.caller_role = 'employer'
      AND c.call_at >= r.created_at
      AND c.call_at <= r.created_at + INTERVAL '7 days'
),
events AS (
    -- Единый поток событий (1 строка = 1 событие)
    SELECT response_id, employer_id, event_id, event_at, event_type FROM messages_7d
    UNION ALL
    SELECT response_id, employer_id, event_id, event_at, event_type FROM calls_7d
)
-- Итог
SELECT
    COUNT(*)                                       AS events_total,
    COUNT(DISTINCT response_id)                    AS responses_with_comm,
    COUNT(*) FILTER (WHERE event_type = 'call')    AS calls_cnt,
    COUNT(*) FILTER (WHERE event_type = 'message') AS messages_cnt
FROM events;


-- Контрольные значения: всего событий 1096; различных откликов с коммуникацией 382;
-- звонков 108; сообщений 988.
-- Вывод. В окно 7 суток попали 108 из 159 звонков работодателя и 988 из 1431 сообщения
-- работодателя (с валидной привязкой к отклику).
-- В слой вошли все статусы звонков: попытка дозвониться (недозвон, тех ошибка) тоже действие работодателя по отклику
-- (из 108: 78 состоявшихся, 29 недозвонов, 1 ошибка).
-- Сообщений в 9 раз больше, чем звонков,т.е. основной канал связи с кандидатом - переписка.

-- ЗАДАНИЕ 3
-- Шаг 1. Слой уровня события (1 строка = 1 событие)
WITH messages_7d AS (
    -- Сообщения работодателя, 7 дней
    SELECT
        m.response_id,
        m.employer_id,
        m.message_id::text AS event_id,
        m.sent_at          AS event_at,
        'message'          AS event_type
    FROM messages AS m
    JOIN responses AS r
        ON r.response_id = m.response_id
    WHERE m.sender_role = 'employer'
      AND m.sent_at >= r.created_at
      AND m.sent_at <= r.created_at + INTERVAL '7 days'
),
calls_7d AS (
    -- Звонки работодателя, 7 дней (JOIN убирает звонки без response_id)
    SELECT
        c.response_id,
        c.employer_id,
        c.call_id::text AS event_id,
        c.call_at       AS event_at,
        'call'          AS event_type
    FROM calls AS c
    JOIN responses AS r
        ON r.response_id = c.response_id
    WHERE c.caller_role = 'employer'
      AND c.call_at >= r.created_at
      AND c.call_at <= r.created_at + INTERVAL '7 days'
),
events AS (
    -- Единый поток событий (1 строка = 1 событие)
    SELECT response_id, employer_id, event_id, event_at, event_type FROM messages_7d
    UNION ALL
    SELECT response_id, employer_id, event_id, event_at, event_type FROM calls_7d
),
timeline AS (
    -- Порядок событий внутри отклика
    SELECT
        e.response_id,
        e.employer_id,
        e.event_id,
        e.event_at,
        e.event_type,
        ROW_NUMBER() OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
        ) AS event_number,
        LAG(e.event_at) OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
        ) AS prev_event_at,
        LEAD(e.event_type) OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
        ) AS next_event_type,
        COUNT(*) OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS comms_so_far,
        FIRST_VALUE(e.event_type) OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
        ) AS first_event_type,
        LAST_VALUE(e.event_type) OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS last_event_type
    FROM events AS e
)
-- Итог: события с признаками последовательности
SELECT
    response_id,
    event_id,
    event_type,
    event_at,
    event_number,
    prev_event_at,
    next_event_type,
    comms_so_far,
    first_event_type,
    last_event_type
FROM timeline
ORDER BY response_id, event_number;


-- Вывод (шаг 1). Строк 1096 (как в предыдущем задании)
-- Порядок внутри отклика устойчивый (event_at, затем event_type, затем event_id, поэтому
-- события с одинаковым временем не прыгают).


-- Шаг 2. Витрина уровня отклика (1 строка = 1 response_id)
WITH messages_7d AS (
    -- Сообщения работодателя, 7 дней
    SELECT
        m.response_id,
        m.employer_id,
        m.message_id::text AS event_id,
        m.sent_at          AS event_at,
        'message'          AS event_type
    FROM messages AS m
    JOIN responses AS r
        ON r.response_id = m.response_id
    WHERE m.sender_role = 'employer'
      AND m.sent_at >= r.created_at
      AND m.sent_at <= r.created_at + INTERVAL '7 days'
),
calls_7d AS (
    -- Звонки работодателя, 7 дней (JOIN убирает звонки без response_id)
    SELECT
        c.response_id,
        c.employer_id,
        c.call_id::text AS event_id,
        c.call_at       AS event_at,
        'call'          AS event_type
    FROM calls AS c
    JOIN responses AS r
        ON r.response_id = c.response_id
    WHERE c.caller_role = 'employer'
      AND c.call_at >= r.created_at
      AND c.call_at <= r.created_at + INTERVAL '7 days'
),
events AS (
    -- Единый поток событий (1 строка = 1 событие)
    SELECT response_id, employer_id, event_id, event_at, event_type FROM messages_7d
    UNION ALL
    SELECT response_id, employer_id, event_id, event_at, event_type FROM calls_7d
),
timeline AS (
    -- Порядок событий внутри отклика
    SELECT
        e.response_id,
        e.employer_id,
        e.event_id,
        e.event_at,
        e.event_type,
        ROW_NUMBER() OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
        ) AS event_number,
        LAG(e.event_at) OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
        ) AS prev_event_at,
        LEAD(e.event_type) OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
        ) AS next_event_type,
        COUNT(*) OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS comms_so_far,
        FIRST_VALUE(e.event_type) OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
        ) AS first_event_type,
        LAST_VALUE(e.event_type) OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS last_event_type
    FROM events AS e
),
response_events AS (
    -- Свертка до отклика (только с коммуникацией)
    SELECT
        t.response_id,
        COUNT(*)                                      AS comm_cnt,
        COUNT(*) FILTER (WHERE t.event_type = 'call')    AS call_cnt,
        COUNT(*) FILTER (WHERE t.event_type = 'message') AS message_cnt,
        MIN(t.event_at)                               AS first_comm_at,
        MAX(t.first_event_type)                       AS first_type,
        MAX(t.event_type) FILTER (WHERE t.event_number = 2) AS second_type,
        MAX(t.last_event_type)                        AS last_type,
        MAX(EXTRACT(EPOCH FROM (t.event_at - t.prev_event_at)) / 3600) AS max_gap_hours
    FROM timeline AS t
    GROUP BY t.response_id
),
response_mart AS (
    -- Витрина откликов (LEFT JOIN сохраняет отклики без коммуникации)
    SELECT
        r.response_id,
        v.employer_id,
        v.professional_role,
        r.status,
        COALESCE(re.comm_cnt, 0)    AS comm_cnt,
        COALESCE(re.call_cnt, 0)    AS call_cnt,
        COALESCE(re.message_cnt, 0) AS message_cnt,
        re.first_comm_at,
        re.first_type,
        re.second_type,
        re.last_type,
        EXTRACT(EPOCH FROM (re.first_comm_at - r.created_at)) / 3600 AS hours_to_first,
        re.max_gap_hours
    FROM responses AS r
    JOIN vacancies AS v
        ON v.vacancy_id = r.vacancy_id
    LEFT JOIN response_events AS re
        ON re.response_id = r.response_id
)
-- Витрина по откликам
SELECT
    response_id,
    employer_id,
    professional_role,
    status,
    comm_cnt,
    call_cnt,
    message_cnt,
    first_comm_at,
    first_type,
    second_type,
    last_type,
    ROUND(hours_to_first::numeric, 2) AS hours_to_first,
    ROUND(max_gap_hours::numeric, 2)  AS max_gap_hours
FROM response_mart
ORDER BY response_id;


-- Вывод (шаг 2). В витрине 628 строк, отклики без коммуникации не потерялись


-- Шаг 3. Контрольные значения по витрине
WITH messages_7d AS (
    -- Сообщения работодателя, 7 дней
    SELECT
        m.response_id,
        m.employer_id,
        m.message_id::text AS event_id,
        m.sent_at          AS event_at,
        'message'          AS event_type
    FROM messages AS m
    JOIN responses AS r
        ON r.response_id = m.response_id
    WHERE m.sender_role = 'employer'
      AND m.sent_at >= r.created_at
      AND m.sent_at <= r.created_at + INTERVAL '7 days'
),
calls_7d AS (
    -- Звонки работодателя, 7 дней (JOIN убирает звонки без response_id)
    SELECT
        c.response_id,
        c.employer_id,
        c.call_id::text AS event_id,
        c.call_at       AS event_at,
        'call'          AS event_type
    FROM calls AS c
    JOIN responses AS r
        ON r.response_id = c.response_id
    WHERE c.caller_role = 'employer'
      AND c.call_at >= r.created_at
      AND c.call_at <= r.created_at + INTERVAL '7 days'
),
events AS (
    -- Единый поток событий (1 строка = 1 событие)
    SELECT response_id, employer_id, event_id, event_at, event_type FROM messages_7d
    UNION ALL
    SELECT response_id, employer_id, event_id, event_at, event_type FROM calls_7d
),
timeline AS (
    -- Порядок событий внутри отклика
    SELECT
        e.response_id,
        e.employer_id,
        e.event_id,
        e.event_at,
        e.event_type,
        ROW_NUMBER() OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
        ) AS event_number,
        LAG(e.event_at) OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
        ) AS prev_event_at,
        LEAD(e.event_type) OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
        ) AS next_event_type,
        COUNT(*) OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS comms_so_far,
        FIRST_VALUE(e.event_type) OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
        ) AS first_event_type,
        LAST_VALUE(e.event_type) OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS last_event_type
    FROM events AS e
),
response_events AS (
    -- Свертка до отклика (только с коммуникацией)
    SELECT
        t.response_id,
        COUNT(*)                                      AS comm_cnt,
        COUNT(*) FILTER (WHERE t.event_type = 'call')    AS call_cnt,
        COUNT(*) FILTER (WHERE t.event_type = 'message') AS message_cnt,
        MIN(t.event_at)                               AS first_comm_at,
        MAX(t.first_event_type)                       AS first_type,
        MAX(t.event_type) FILTER (WHERE t.event_number = 2) AS second_type,
        MAX(t.last_event_type)                        AS last_type,
        MAX(EXTRACT(EPOCH FROM (t.event_at - t.prev_event_at)) / 3600) AS max_gap_hours
    FROM timeline AS t
    GROUP BY t.response_id
),
response_mart AS (
    -- Витрина откликов (LEFT JOIN сохраняет отклики без коммуникации)
    SELECT
        r.response_id,
        v.employer_id,
        v.professional_role,
        r.status,
        COALESCE(re.comm_cnt, 0)    AS comm_cnt,
        COALESCE(re.call_cnt, 0)    AS call_cnt,
        COALESCE(re.message_cnt, 0) AS message_cnt,
        re.first_comm_at,
        re.first_type,
        re.second_type,
        re.last_type,
        EXTRACT(EPOCH FROM (re.first_comm_at - r.created_at)) / 3600 AS hours_to_first,
        re.max_gap_hours
    FROM responses AS r
    JOIN vacancies AS v
        ON v.vacancy_id = r.vacancy_id
    LEFT JOIN response_events AS re
        ON re.response_id = r.response_id
)
-- Итог: 5 контрольных значений
SELECT
    COUNT(*)                                        AS mart_rows,
    COUNT(*) FILTER (WHERE comm_cnt > 0)            AS responses_with_comm,
    COUNT(*) FILTER (WHERE comm_cnt = 0)            AS responses_without_comm,
    COUNT(*) FILTER (WHERE first_type = 'message')  AS first_is_message,
    COUNT(*) FILTER (WHERE first_type = 'call')     AS first_is_call
FROM response_mart;


-- Контрольные значения: строк в витрине 628; откликов с коммуникацией 382; без коммуникации 246;
-- первой коммуникацией было сообщение в 314 откликах; звонок в 68.
-- Вывод. Работодатель вышел на связь в течение 7 суток по 60,8% откликов, а по 39,2% (246) не было
-- ни звонка, ни сообщения. Когда контакт случается, он начинается с сообщения в 82% случаев (314 из 382).


-- ============================================================
-- БЛОК В. Сравнение работодателей
-- ============================================================

-- ЗАДАНИЕ 4
WITH messages_7d AS (
    -- Сообщения работодателя, 7 дней
    SELECT
        m.response_id,
        m.employer_id,
        m.message_id::text AS event_id,
        m.sent_at          AS event_at,
        'message'          AS event_type
    FROM messages AS m
    JOIN responses AS r
        ON r.response_id = m.response_id
    WHERE m.sender_role = 'employer'
      AND m.sent_at >= r.created_at
      AND m.sent_at <= r.created_at + INTERVAL '7 days'
),
calls_7d AS (
    -- Звонки работодателя, 7 дней (JOIN убирает звонки без response_id)
    SELECT
        c.response_id,
        c.employer_id,
        c.call_id::text AS event_id,
        c.call_at       AS event_at,
        'call'          AS event_type
    FROM calls AS c
    JOIN responses AS r
        ON r.response_id = c.response_id
    WHERE c.caller_role = 'employer'
      AND c.call_at >= r.created_at
      AND c.call_at <= r.created_at + INTERVAL '7 days'
),
events AS (
    -- Единый поток событий (1 строка = 1 событие)
    SELECT response_id, employer_id, event_id, event_at, event_type FROM messages_7d
    UNION ALL
    SELECT response_id, employer_id, event_id, event_at, event_type FROM calls_7d
),
timeline AS (
    -- Порядок событий внутри отклика
    SELECT
        e.response_id,
        e.employer_id,
        e.event_id,
        e.event_at,
        e.event_type,
        ROW_NUMBER() OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
        ) AS event_number,
        LAG(e.event_at) OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
        ) AS prev_event_at,
        LEAD(e.event_type) OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
        ) AS next_event_type,
        COUNT(*) OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS comms_so_far,
        FIRST_VALUE(e.event_type) OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
        ) AS first_event_type,
        LAST_VALUE(e.event_type) OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS last_event_type
    FROM events AS e
),
response_events AS (
    -- Свертка до отклика (только с коммуникацией)
    SELECT
        t.response_id,
        COUNT(*)                                      AS comm_cnt,
        COUNT(*) FILTER (WHERE t.event_type = 'call')    AS call_cnt,
        COUNT(*) FILTER (WHERE t.event_type = 'message') AS message_cnt,
        MIN(t.event_at)                               AS first_comm_at,
        MAX(t.first_event_type)                       AS first_type,
        MAX(t.event_type) FILTER (WHERE t.event_number = 2) AS second_type,
        MAX(t.last_event_type)                        AS last_type,
        MAX(EXTRACT(EPOCH FROM (t.event_at - t.prev_event_at)) / 3600) AS max_gap_hours
    FROM timeline AS t
    GROUP BY t.response_id
),
response_mart AS (
    -- Витрина откликов (LEFT JOIN сохраняет отклики без коммуникации)
    SELECT
        r.response_id,
        v.employer_id,
        v.professional_role,
        r.status,
        COALESCE(re.comm_cnt, 0)    AS comm_cnt,
        COALESCE(re.call_cnt, 0)    AS call_cnt,
        COALESCE(re.message_cnt, 0) AS message_cnt,
        re.first_comm_at,
        re.first_type,
        re.second_type,
        re.last_type,
        EXTRACT(EPOCH FROM (re.first_comm_at - r.created_at)) / 3600 AS hours_to_first,
        re.max_gap_hours
    FROM responses AS r
    JOIN vacancies AS v
        ON v.vacancy_id = r.vacancy_id
    LEFT JOIN response_events AS re
        ON re.response_id = r.response_id
),
employer_role_stats AS (
    -- Метрики по паре роль + работодатель
    SELECT
        professional_role,
        employer_id,
        COUNT(*)                                    AS responses_cnt,
        COUNT(*) FILTER (WHERE comm_cnt > 0)        AS processed_cnt,
        ROUND(100.0 * COUNT(*) FILTER (WHERE comm_cnt > 0)
              / NULLIF(COUNT(*), 0), 1)             AS processed_pct,
        -- перцентили пропускают NULL: считаем только отклики с контактом
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY hours_to_first) AS median_hours_to_first,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY hours_to_first) AS p90_hours_to_first,
        ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'invited')
              / NULLIF(COUNT(*), 0), 1)             AS invite_conversion_pct
    FROM response_mart
    GROUP BY professional_role, employer_id
    HAVING COUNT(*) >= 8
),
ranked AS (
    -- Места внутри направления
    SELECT
        s.professional_role,
        s.employer_id,
        s.responses_cnt,
        s.processed_cnt,
        s.processed_pct,
        s.median_hours_to_first,
        s.p90_hours_to_first,
        s.invite_conversion_pct,
        -- DENSE_RANK: ничья дает одно место, без пропуска номеров
        DENSE_RANK() OVER (
            PARTITION BY professional_role
            ORDER BY processed_cnt::numeric / responses_cnt DESC,
                     median_hours_to_first ASC
        ) AS place
    FROM employer_role_stats AS s
)
-- Итог: 1 и 2 места по направлениям
SELECT
    professional_role,
    place,
    employer_id,
    responses_cnt,
    processed_cnt,
    processed_pct,
    ROUND(median_hours_to_first::numeric, 2) AS median_hours_to_first,
    ROUND(p90_hours_to_first::numeric, 2)    AS p90_hours_to_first,
    invite_conversion_pct
FROM ranked
WHERE place <= 2
ORDER BY professional_role, place, employer_id;


-- Итоговый рейтинг (professional_role, место, employer_id):
-- Аналитик данных	1	109
-- Аналитик данных	2	103
-- Дата-инженер	1	106
-- Дата-инженер	2	101
-- Продуктовый аналитик	1	103
-- Продуктовый аналитик	2	102
-- Разработчик	1	112
-- Разработчик	2	104
-- Тестировщик	1	107
-- Тестировщик	2	108

-- Вывод.
-- В рейтинг попали 18 пар «направление + работодатель» с 8 и более откликами, в топ-2 вошли 10.
-- Ничьих по обоим критериям нет (т.е. по сути DENSE_RANK здесь не отличается от RANK)
-- Разброс между работодателями внутри направления местами большой: например у дата-инженеров лидер 106 обработал 70% откликов, а работодатель 101 только 45,8%.
-- Есть маленькие выборки (пары с 8–31 откликом), поэтому рейтинг лишь повод для вопросов, а не окончательный вердикт.
-- Конверсия в приглашение по месту в рейтинге скорости не упорядочена: у тестировщиков она 41,2% и 37,5% у обоих лидеров,
-- у аналитиков данных 15,8% и 10,1%, т.е.  конверсия скорее сильнее зависит от направления, чем от скорости работодателя.



-- ЗАДАНИЕ 5
WITH messages_7d AS (
    -- Сообщения обеих сторон, 7 дней
    SELECT m.message_id, m.response_id, m.employer_id, m.sender_role, m.sent_at
    FROM messages AS m
    JOIN responses AS r
        ON r.response_id = m.response_id
    WHERE m.sent_at >= r.created_at
      AND m.sent_at <= r.created_at + INTERVAL '7 days'
),
message_pairs AS (
    -- Предыдущее сообщение в отклике
    SELECT
        message_id,
        response_id,
        employer_id,
        sender_role,
        sent_at,
        LAG(sender_role) OVER (PARTITION BY response_id ORDER BY sent_at, message_id) AS prev_sender_role,
        LAG(sent_at)     OVER (PARTITION BY response_id ORDER BY sent_at, message_id) AS prev_sent_at
    FROM messages_7d
),
employer_replies AS (
    -- Ответы работодателя после кандидата
    SELECT
        employer_id,
        EXTRACT(EPOCH FROM (sent_at - prev_sent_at)) / 3600 AS reply_hours
    FROM message_pairs
    WHERE sender_role = 'employer'
      AND prev_sender_role = 'applicant'
)
-- Итог: скорость ответа по работодателям
SELECT
    employer_id,
    COUNT(*)                                                   AS replies_cnt,
    SUM(COUNT(*)) OVER ()                                      AS replies_total,
    ROUND(AVG(reply_hours)::numeric, 2)                        AS avg_reply_hours,
    ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY reply_hours))::numeric, 2) AS median_reply_hours,
    ROUND((PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY reply_hours))::numeric, 2) AS p90_reply_hours
FROM employer_replies
GROUP BY employer_id
ORDER BY median_reply_hours ASC, employer_id;


-- Контрольные значения: всего найдено ответов 749; минимальная медиана у работодателя 107 (медиана 3,93 часа (28 ответов)).
-- Вывод. Работодатели отвечают на сообщения кандидата довольно быстро и примерно одинаково: медианы
-- по 11 работодателям лежат в узком диапозоне 3,9–4,9 часов.
-- Работодателя 111 в таблице нет т.к. на его вакансию вообще нет откликов.
-- Опять же влюяют размеры выборок: например лидерство 107 над 108 (4,12 ч) и 110 (4,13 ч) - это разница в
-- десятые доли часа при 28 ответах, поэтому уверенно называть его самым быстрым нельзя.
-- Для сравнения: до первого контакта ждут около двух суток, а диалог идет со скоростью
-- несколько часов на реплику, поэтому коммуникацию можно считать довольно быстрой.


-- ============================================================
-- БЛОК Г. Сложные типы данных
-- ============================================================

-- ЗАДАНИЕ 6
-- 6.1. Теги звонков работодателя в первые 7 суток
WITH calls_7d AS (
    -- Звонки работодателя, 7 дней
    SELECT c.call_id, c.status, c.call_tags
    FROM calls AS c
    JOIN responses AS r
        ON r.response_id = c.response_id
    WHERE c.caller_role = 'employer'
      AND c.call_at >= r.created_at
      AND c.call_at <= r.created_at + INTERVAL '7 days'
),
calls_checked AS (
    -- Проверка тегов по статусу
    SELECT
        call_id,
        call_tags,
        -- Бизнес-теги звонка (массив без технических тегов)
        CARDINALITY(ARRAY(
            SELECT tag FROM UNNEST(call_tags) AS tag
            WHERE tag IN ('screening', 'interview', 'follow_up', 'details')
        )) AS business_tags_cnt,
        (
               (status = 'successful'   AND 'connected' = ANY(call_tags)
                    AND NOT ('no_answer' = ANY(call_tags) OR 'technical_error' = ANY(call_tags)))
            OR (status = 'unsuccessful' AND 'no_answer' = ANY(call_tags)
                    AND NOT ('connected' = ANY(call_tags) OR 'technical_error' = ANY(call_tags)))
            OR (status = 'error'        AND 'technical_error' = ANY(call_tags)
                    AND NOT ('connected' = ANY(call_tags) OR 'no_answer' = ANY(call_tags)))
        ) AS tags_consistent
    FROM calls_7d
)
-- Итог: счетчики по тегам
SELECT
    COUNT(*)                                               AS calls_total,
    COUNT(*) FILTER (WHERE NOT tags_consistent)            AS contradictions,
    COUNT(*) FILTER (WHERE tags_consistent)                AS valid_calls,
    COUNT(*) FILTER (WHERE tags_consistent AND 'screening' = ANY(call_tags)) AS screening_cnt,
    COUNT(*) FILTER (WHERE tags_consistent AND 'interview' = ANY(call_tags)) AS interview_cnt,
    COUNT(*) FILTER (WHERE tags_consistent AND 'follow_up' = ANY(call_tags)) AS follow_up_cnt,
    COUNT(*) FILTER (WHERE tags_consistent AND 'details'   = ANY(call_tags)) AS details_cnt,
    COUNT(*) FILTER (WHERE tags_consistent
                       AND call_tags && ARRAY['screening', 'interview', 'follow_up', 'details']) AS calls_with_business_tag,
    ROUND(AVG(CARDINALITY(call_tags)) FILTER (WHERE tags_consistent), 2) AS avg_tags_per_call,
    ROUND(AVG(business_tags_cnt) FILTER (WHERE tags_consistent), 2)      AS avg_business_tags_per_call
FROM calls_checked;


-- Контрольные значения: звонков 108; противоречий тегов и status 0, то есть валидных 108;
-- screening 25; interview 31; follow_up 29; details 23; валидных звонков хотя бы с одним
-- бизнес-тегом 108; среднее количество тегов на валидный звонок 4,00 (из них бизнес-тегов 1,00).
-- Вывод. Технические теги везде согласуются со status. Сумма бизнес-тегов 25 + 31 + 29 + 23
-- дает ровно 108, то есть у каждого звонка ровно один бизнес-тег; вместе с тегом voice, техническим
-- тегом (connected / no_answer / technical_error) и тегом направления получается 4 тега на звонок. Чаще всего звонят по поводу интервью (31) и
-- follow-up (29), реже по деталям (23) и скринингу (25).


-- 6.2. Метаданные сообщений работодателя в первые 7 суток
WITH messages_7d AS (
    -- Сообщения работодателя, 7 дней
    SELECT m.message_id, m.message_meta
    FROM messages AS m
    JOIN responses AS r
        ON r.response_id = m.response_id
    WHERE m.sender_role = 'employer'
      AND m.sent_at >= r.created_at
      AND m.sent_at <= r.created_at + INTERVAL '7 days'
),
parsed AS (
    -- Поля из message_meta (->> дает NULL, если ключа нет)
    SELECT
        message_id,
        COALESCE(message_meta ->> 'channel', 'не указан') AS channel,
        (message_meta ->> 'is_read')::boolean              AS is_read,
        CASE JSONB_TYPEOF(message_meta -> 'attachments')
            WHEN 'array'  THEN JSONB_ARRAY_LENGTH(message_meta -> 'attachments')
            WHEN 'number' THEN (message_meta ->> 'attachments')::integer
        END                                                AS attachments_cnt
    FROM messages_7d
)
-- Итог: метрики по каналам
SELECT
    channel,
    COUNT(*)                                            AS messages_cnt,
    COUNT(is_read)                                      AS read_flag_known,
    COUNT(*) FILTER (WHERE is_read = FALSE)             AS unread_cnt,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_read = FALSE)
          / NULLIF(COUNT(is_read), 0), 1)               AS unread_pct,
    COUNT(*) FILTER (WHERE attachments_cnt >= 1)        AS with_attachment_cnt,
    ROUND(100.0 * COUNT(*) FILTER (WHERE attachments_cnt >= 1)
          / NULLIF(COUNT(*), 0), 1)                     AS with_attachment_pct
FROM parsed
GROUP BY channel
ORDER BY messages_cnt DESC;


-- Контрольные значения (канал, сообщений, признак прочтения известен, непрочитано, доля
-- непрочитанных, с вложением, доля с вложением):
-- web	        628	628	52	8.3	 25	4.0
-- mobile_app	360	360	36	10.0 14	3.9
-- Группа «не указан» пуста: канал есть у всех сообщений.
-- Вывод. 64% сообщений уходят через web и 36% через mobile_app. Не прочитано около 9%
-- сообщений (88 из 988), в мобильном приложении чуть чаще (10,0% против 8,3%), но разница в
-- 1,7%  при 360 сообщениях мала, чтобы считать ее устойчивой. Вложения встречаются редко,
-- в 3,9–4,0% сообщений, и от канала не зависят. Количество вложений считалось как длина
-- массива attachments.


-- ============================================================
-- БЛОК Д. Самостоятельное исследование
-- ============================================================

-- ЗАДАНИЕ 7
-- Вопрос продукта: чем коммуникации по откликам, закончившимся приглашением (status = 'invited'),
-- отличаются от остальных откликов. Сравниваем две группы: «приглашение» и «без приглашения».
-- Гипотезы:
-- Г1 (скорость). Работодатель быстрее реагирует на отклики, которые в итоге заканчиваются
--    приглашением: по ним чаще бывает контакт, он начинается раньше и чаще укладывается в сутки.
-- Г2 (интенсивность, канал и содержание). По откликам с приглашением коммуникация плотнее
--    и разнообразнее: в среднем больше событий на отклик, чаще звонят и используют оба канала,
--    чаще проводят состоявшийся звонок с тегом interview.
-- Показатели: доля откликов с контактом; медиана часов до первой коммуникации; доля откликов с
-- первой коммуникацией в течение 24 часов (новый показатель); среднее число коммуникаций на отклик;
-- доля откликов со звонком; доля откликов, где использованы оба канала (новый показатель); доля
-- откликов с состоявшимся звонком interview (новый показатель, использует теги звонков).
-- Все доли считаются от всех откликов группы, в колонках responses_cnt и contacted_cnt — размер
-- выборки (медиана считается только по откликам с контактом).

WITH messages_7d AS (
    -- Сообщения работодателя, 7 дней
    SELECT
        m.response_id,
        m.employer_id,
        m.message_id::text AS event_id,
        m.sent_at          AS event_at,
        'message'          AS event_type
    FROM messages AS m
    JOIN responses AS r
        ON r.response_id = m.response_id
    WHERE m.sender_role = 'employer'
      AND m.sent_at >= r.created_at
      AND m.sent_at <= r.created_at + INTERVAL '7 days'
),
calls_7d AS (
    -- Звонки работодателя, 7 дней (JOIN убирает звонки без response_id)
    SELECT
        c.response_id,
        c.employer_id,
        c.call_id::text AS event_id,
        c.call_at       AS event_at,
        'call'          AS event_type
    FROM calls AS c
    JOIN responses AS r
        ON r.response_id = c.response_id
    WHERE c.caller_role = 'employer'
      AND c.call_at >= r.created_at
      AND c.call_at <= r.created_at + INTERVAL '7 days'
),
events AS (
    -- Единый поток событий (1 строка = 1 событие)
    SELECT response_id, employer_id, event_id, event_at, event_type FROM messages_7d
    UNION ALL
    SELECT response_id, employer_id, event_id, event_at, event_type FROM calls_7d
),
timeline AS (
    -- Порядок событий внутри отклика
    SELECT
        e.response_id,
        e.employer_id,
        e.event_id,
        e.event_at,
        e.event_type,
        ROW_NUMBER() OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
        ) AS event_number,
        LAG(e.event_at) OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
        ) AS prev_event_at,
        LEAD(e.event_type) OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
        ) AS next_event_type,
        COUNT(*) OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS comms_so_far,
        FIRST_VALUE(e.event_type) OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
        ) AS first_event_type,
        LAST_VALUE(e.event_type) OVER (
            PARTITION BY e.response_id
            ORDER BY e.event_at, e.event_type, e.event_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS last_event_type
    FROM events AS e
),
response_events AS (
    -- Свертка до отклика (только с коммуникацией)
    SELECT
        t.response_id,
        COUNT(*)                                      AS comm_cnt,
        COUNT(*) FILTER (WHERE t.event_type = 'call')    AS call_cnt,
        COUNT(*) FILTER (WHERE t.event_type = 'message') AS message_cnt,
        MIN(t.event_at)                               AS first_comm_at,
        MAX(t.first_event_type)                       AS first_type,
        MAX(t.event_type) FILTER (WHERE t.event_number = 2) AS second_type,
        MAX(t.last_event_type)                        AS last_type,
        MAX(EXTRACT(EPOCH FROM (t.event_at - t.prev_event_at)) / 3600) AS max_gap_hours
    FROM timeline AS t
    GROUP BY t.response_id
),
response_mart AS (
    -- Витрина откликов (LEFT JOIN сохраняет отклики без коммуникации)
    SELECT
        r.response_id,
        v.employer_id,
        v.professional_role,
        r.status,
        COALESCE(re.comm_cnt, 0)    AS comm_cnt,
        COALESCE(re.call_cnt, 0)    AS call_cnt,
        COALESCE(re.message_cnt, 0) AS message_cnt,
        re.first_comm_at,
        re.first_type,
        re.second_type,
        re.last_type,
        EXTRACT(EPOCH FROM (re.first_comm_at - r.created_at)) / 3600 AS hours_to_first,
        re.max_gap_hours
    FROM responses AS r
    JOIN vacancies AS v
        ON v.vacancy_id = r.vacancy_id
    LEFT JOIN response_events AS re
        ON re.response_id = r.response_id
),
response_features AS (
    -- Признаки отклика + группа исхода
    SELECT
        m.response_id,
        CASE WHEN m.status = 'invited' THEN 'приглашение' ELSE 'без приглашения' END AS outcome_group,
        m.comm_cnt,
        m.call_cnt,
        m.message_cnt,
        m.hours_to_first,
        -- есть ли состоявшийся звонок работодателя с тегом interview за 7 дней
        EXISTS (
            SELECT 1
            FROM calls AS c
            JOIN responses AS r
                ON r.response_id = c.response_id
            WHERE c.response_id = m.response_id
              AND c.caller_role = 'employer'
              AND c.status = 'successful'
              AND 'interview' = ANY(c.call_tags)
              AND c.call_at >= r.created_at
              AND c.call_at <= r.created_at + INTERVAL '7 days'
        ) AS has_interview_call
    FROM response_mart AS m
)
-- Итог: сравнение двух групп
SELECT
    outcome_group,
    COUNT(*)                                                           AS responses_cnt,
    COUNT(*) FILTER (WHERE comm_cnt > 0)                               AS contacted_cnt,
    -- скорость
    ROUND(100.0 * COUNT(*) FILTER (WHERE comm_cnt > 0) / NULLIF(COUNT(*), 0), 1)         AS contacted_pct,
    ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY hours_to_first))::numeric, 1)    AS median_hours_to_first,
    ROUND(100.0 * COUNT(*) FILTER (WHERE hours_to_first <= 24) / NULLIF(COUNT(*), 0), 1) AS contacted_24h_pct,
    -- интенсивность и канал
    ROUND(AVG(comm_cnt), 2)                                            AS avg_comms_per_response,
    ROUND(100.0 * COUNT(*) FILTER (WHERE call_cnt > 0) / NULLIF(COUNT(*), 0), 1)         AS any_call_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE call_cnt > 0 AND message_cnt > 0)
          / NULLIF(COUNT(*), 0), 1)                                    AS both_channels_pct,
    -- содержание: звонок с тегом interview
    COUNT(*) FILTER (WHERE has_interview_call)                         AS interview_call_cnt,
    ROUND(100.0 * COUNT(*) FILTER (WHERE has_interview_call) / NULLIF(COUNT(*), 0), 1)   AS interview_call_pct
FROM response_features
GROUP BY outcome_group
ORDER BY outcome_group DESC;


-- Результат (приглашение / без приглашения):
-- откликов 92 / 536; с контактом 54 / 328; доля с контактом 58,7% / 61,2%; медиана часов до первой
-- коммуникации 51,1 / 54,7; контакт в течение 24 часов 19,6% / 19,4%; коммуникаций на отклик
-- 1,63 / 1,76; доля со звонком 16,3% / 16,4%; оба канала 8,7% / 10,6%; звонок interview
-- 4,3% (4 отклика) / 2,8% (15 откликов).
-- Погрешность долей в группе приглашенных из за 92 откликов около +-10% для доли с контактом,
-- +-8% для доли в 24 часа и +-7,5% для доли со звонком (формула 1,96·sqrt(p(1−p)/n)), то есть
-- все разницы между группами заметно меньше погрешности.
-- Г1: не подтверждается. Контакт по приглашенным откликам случается даже реже (58,7% против 61,2%),
-- первая коммуникация в сутки укладывается практически одинаково (19,6% и 19,4%); медиана у
-- приглашенных меньше на 3,6 часа, но при медиане около двух суток и 54 приглашенных с контактом
-- это не отличается от шума.
-- Г2: не подтверждается. Среднее число коммуникаций у приглашенных даже ниже (1,63 против 1,76),
-- доля со звонком одинакова (16,3% и 16,4%), оба канала реже (8,7% против 10,6%). Единственный
-- сдвиг в нужную сторону - звонок interview (4,3% против 2,8%), но за ним 4 отклика в группе
-- приглашенных, так что по этому отдельному показателю данных недостаточно.
-- Итог: по характеристикам первых 7 суток отклики с приглашением не отличаются от остальных.


-- ============================================================
-- ЗАДАНИЕ 8. Итог исследования
-- ============================================================

-- 1. В первые 7 суток работодатели вышли на связь по 382 из 628 откликов (60,8%), а по 246 (39,2%)
--    не было ни звонка, ни сообщения (задания 2–3).
-- 2. Контакт обычно начинается с сообщения (314 из 382 откликов, 82%), всего за 7 суток набралось
--    1096 событий: 988 сообщений и только 108 звонков.
-- 3. С первым шагом работодатели обычнр не спешат: медиана времени до первой коммуникации около 54 часов,
--    в течение суток контакт получили лишь 19,4% всех откликов.
-- 4. Когда диалог начался, ответы быстрые: по 749 ответам на сообщения кандидатов медианы у
--    работодателей лежат в диапазоне 3,9–4,9 часа (задание 5).
-- 5. Между работодателями внутри направления разброс заметный, например у дата-инженеров 70,0% против
--    45,8% обработанных откликов, а между направлениями сильно отличается конверсия в приглашение: у
--    лидеров рейтинга среди тестировщиков 41,2% и 37,5% против 10–20% в остальных направлениях (задание 4).
-- 6. Отклики с приглашением и без него по коммуникации в первые 7 суток почти не различаются: контакт
--    получили 58,7% против 61,2%, медиана до первой коммуникации 51,1 против 54,7 часа, звонок был в
--    16,3% против 16,4% (задание 7), то есть ни скорость, не канал приглашение не предсказывают.
-- 7. Это лишь наблюдаемая связь, а не причинность, и у анализа есть ограничения: приглашенных откликов всего
--    92 (погрешность долей около +-4–10%), status показывает текущее состояние отклика на момент
--    выгрузки, а 8 звонков без response_id пришлось исключить из-за недоверия к связи с откликом (задание 1).
-- 8. Следующий вопрос: что происходит после 7 суток (в базе еще 886 сообщений и 75 звонков за пределами
--    окна) и когда именно менялся статус отклика на «приглашен»; для этого нужен журнал смены статусов с
--    датами, чтобы понять, что было раньше: коммуникация или решение пригласить.
-- ============================================================
-- Домашнее задание к лекции «SQL. Введение»
-- Школа Аналитиков · учебная база hh_school
-- Автор: Мельников Тимофей Валерьевич
-- ============================================================
SET search_path TO hh_school;


-- ============================================================
-- БЛОК А. Разминка: термины и структура (текстом)
-- ============================================================

-- ЗАДАНИЕ А1
-- 1. Категория и конкретный тип колонок:
--    vacancies.salary_from        — категория: числовой           тип: INTEGER
--    vacancies.vacancy_name       — категория: строковый          тип: TEXT
--    vacancies.published_at       — категория: дата и время       тип: TIMESTAMP
--    employers.is_accredited_it   — категория: логический         тип: BOOLEAN
--    responses.created_at         — категория: дата и время       тип: TIMESTAMP
--
-- 2. Первичные ключи таблиц:
--    areas: area_id
--    employers: employer_id
--    responses: response_id
--    vacancies: vacancy_id
--    vacancy_details: vacancy_id (это одновременно первичный и внешний
--      ключ на vacancies.vacancy_id (по сути связь 1 к 1). Еще заметил что vacancy_details есть
--      не у всех вакансий
--
-- 3. Почему vacancy_name не может быть первичным ключом:
--    Первичный ключ должен быть уникальным и не NULL, а названия вакансий повторяются
--    (разные компании, города и даты имеют одно название вакансии).
--    Также у колонки NOT NULL = false, то есть название может вообще отсутствовать.
--    Запрос для подтверждения числом:
SELECT vacancy_name,
       count(*) AS cnt
FROM vacancies
GROUP BY vacancy_name
ORDER BY cnt DESC
LIMIT 1;

-- Вывод:
-- Самое частое название "Стажёр: аналитик данных" встречается 6 раз. Всего в базе
-- 52 вакансии, при этом названия не уникальны, так что по названию вакансию однозначно
-- не найти. Для этого и нужен vacancy_id.
--
-- 4. Что произойдёт при записи строки «по договорённости» в salary_from:
--    Postgres выдаст ошибку так как salary_from имеет тип integer, а "по договорённости" это текст,
--    и строка не запишется. Это хорошо, т.к. в колонке гарантированно лежат только числа (или NULL),
--    поэтому нет никакой путаницы при использовании агр функций, сортировки и тд.


-- ============================================================
-- БЛОК Б. Первые запросы: SELECT, WHERE, ORDER BY
-- ============================================================

-- ЗАДАНИЕ Б1
-- Запрос: experience
SELECT DISTINCT experience
FROM vacancies
ORDER BY experience;

-- Запрос: employment
SELECT DISTINCT employment
FROM vacancies
ORDER BY employment;

-- Запрос: professional_role
SELECT DISTINCT professional_role
FROM vacancies
ORDER BY professional_role;

-- Вывод:
-- В experience 3 уникальных значения, в employment 3, в professional_role 5
-- Пустых значенийй (NULL) нет
-- Одно и то же значение по разному не записано
-- Подмечу что в expirience нету категории более 6 лет, но это нормально


-- ЗАДАНИЕ Б2
-- Запрос 1: стажировки в Москве без опыта, вакансия открыта
SELECT vacancy_id,
       vacancy_name,
       salary_from,
       published_at
FROM vacancies
WHERE area_id = 1 -- не стал джойнить, просто посмотрел id Москвы
  AND employment = 'Стажировка'
  AND experience = 'Нет опыта'
  AND closed_at IS NULL
ORDER BY published_at DESC;

-- Вывод:
-- Есть 8 открытых московских стажировок без опыта, это около 42% от
-- всех 19 стажировок в базе. Свежих (с мая) среди них только 4, остальные четыре в
-- висят с января по март, у одной из них зарплата не указана.
-- Если убрать условие про Москву, останется 10 вакансий (добавятся 2 из Санкт-Петербурга и Екатеринбурга).

-- Запрос 2: топ-10 вакансий по salary_from
SELECT vacancy_name,
       professional_role,
       salary_from
FROM vacancies
ORDER BY salary_from DESC NULLS last -- NULLS last чтобы спереди не было пустых зарплат
LIMIT 10;

-- Вывод:
-- Наибольшая левая граница зарплатной вилки среди вакансий наблюдается у специалистов уровня Senior,
-- в таких областях как разработка и дата инженерия. В топ-10 также входят аналитика данных и тестирование.

-- ЗАДАНИЕ Б3
-- Ловушка 1. NULL — выполнить и объяснить результат
SELECT count(*) FROM vacancies WHERE closed_at = NULL;
SELECT count(*) FROM vacancies WHERE closed_at IS NULL;

-- Ловушка 2. AND / OR — выполнить и объяснить результат
SELECT count(*) FROM vacancies
WHERE area_id = 1 OR area_id = 2 AND experience = 'Нет опыта';

SELECT count(*) FROM vacancies
WHERE (area_id = 1 OR area_id = 2) AND experience = 'Нет опыта';

-- Вывод:
-- 1) NULL: первый запрос вернул 0, второй 33. Сравнение = NULL даёт не TRUE,
-- а неопределенность, поэтому не одна строка не проходит фильтр.
-- Это опасно, потому что ошибки нет, и можно подумать что пропуски отсутствуют, хотя на деле их 33.
-- NULL в closed_at означает, что вакансия еще не закрыта (нет записи о закрытии), то есть открыта.
-- 2) AND/OR: AND приоритетнее OR, поэтому первое условие база прочитала как
-- "вся Москва ИЛИ (Санкт Петербург и без опыта)".
-- На вопрос "Москва или Санкт Петербург, но обязательно без опыта" отвечает второй запрос.


-- ============================================================
-- БЛОК В. Агрегации и метрики
-- ============================================================

-- ЗАДАНИЕ В1
-- Запрос 1: счётчики (строки, зарплата указана, направления, работодатели)
SELECT count(*)                         AS total_rows,
       count(salary_from)               AS with_salary_from,
       count(DISTINCT professional_role) AS roles,
       count(DISTINCT employer_id)      AS employers
FROM vacancies;

-- Запрос 2: доля активных вакансий (без JOIN)
SELECT count(*) FILTER (WHERE closed_at IS NULL) AS open_cnt,
       count(*) FILTER (WHERE closed_at IS NOT NULL) AS closed_cnt,
       round(100.0 * count(*) FILTER (WHERE closed_at IS NULL) / nullif(count(*), 0), 1) AS open_pct
FROM vacancies;

-- Вывод:
-- count(*) считает все строки (52),
-- count(salary_from) только те, где значение не NULL (44, у 8 вакансий зарплата не указана),
---count(DISTINCT professional_role) считает уникальные значения (всего 5 направлений),
-- employer_id аналогично (12 работодателей).
-- Ответ руководителю: «Сейчас открыто 33 вакансии из 52, то есть 63,5%».


-- ЗАДАНИЕ В2
-- Запрос 1: направления — вакансии, работодатели, средняя зарплата
SELECT professional_role,
       count(*)                    AS vacancies,
       count(DISTINCT employer_id) AS employers,
       round(avg(salary_from))     AS avg_salary_from
FROM vacancies
GROUP BY professional_role
ORDER BY vacancies DESC;

-- Запрос 2: то же, только направления с ≥ 5 открытыми вакансиями (WHERE + HAVING)
SELECT professional_role,
       count(*)                    AS vacancies,
       count(DISTINCT employer_id) AS employers,
       round(avg(salary_from))     AS avg_salary_from
FROM vacancies
WHERE closed_at IS NULL
GROUP BY professional_role
HAVING count(*) >= 5
ORDER BY vacancies DESC;

-- Вывод:
-- Больше половины рынка занимают «Аналитик данных» (16) и «Разработчик» (15): 31 из 52 вакансий, около 60%.
-- Соискатель по такой таблице решил бы, что идти надо туда где больше вакансий,
-- но в ней нет информации об отликах (то есть конкуренции),конверсии в
-- приглашения и уровня вакансий, так что для вывода данных мало.
-- Открытость вакансии это условие на отдельные строки, мы его проверяем до группировки,
-- поэтому оно в WHERE. count(*) >= 5 это условие на группу, которое существует только
-- после группировки, поэтому оно в HAVING. WHERE count(*) >= 5 дало бы ошибку, т.к. в WHERE
-- агр функции не логичны потому что на этом этапе еще нет групп.
-- avg(salary_from) отвечает на вопрос «какая в среднем нижняя граница вилки в
-- вакансиях, где зарплата указана» (NULL пропускаются). Он не отвечает на вопрос
-- «сколько платят в этом направлении» потому что в среднем смешаны и стажеры и senior с разными зп,
-- к тому же это только нижняя граница, а не реальная зарплата.


-- ============================================================
-- БЛОК Г. Соединение таблиц
-- ============================================================

-- ЗАДАНИЕ Г1
-- Запрос: топ-5 по salary_from с названием компании и городом (псевдонимы таблиц)
SELECT v.vacancy_name,
       e.employer_name,
       a.area_name,
       v.salary_from
FROM vacancies v
JOIN employers e ON e.employer_id = v.employer_id
JOIN areas a     ON a.area_id = v.area_id
ORDER BY v.salary_from DESC NULLS LAST
LIMIT 5;

-- Вывод:
-- Самые высокие нижние границы у Senior-вакансий: разработчика с 195 тыс. (Северный Код, Санкт- Петербург),
-- дата инженера с 190 тыс. (УралСофт, Екатеринбург). Дальше с отрывом 45 тыс. идут 3 вакансии аналитиков данных.
-- Если убрать псевдонимы и написать просто area_id, Postgres выдаст ошибку «column reference "area_id" is ambiguous», т.е.
-- колонка с таким именем есть и в vacancies и в areas, и база не знает какую взять.


-- ЗАДАНИЕ Г2
-- Запрос 1: все работодатели, число вакансий и откликов (LEFT JOIN)
SELECT e.employer_name,
       count(distinct v.vacancy_id) AS vacancies,
       count(r.response_id)         AS responses
FROM employers e
LEFT JOIN vacancies v ON v.employer_id = e.employer_id
LEFT JOIN responses r ON r.vacancy_id = v.vacancy_id
GROUP BY e.employer_id, e.employer_name
ORDER BY responses DESC, e.employer_name;

-- Запрос 2: тот же запрос с INNER JOIN
SELECT e.employer_name,
       count(DISTINCT v.vacancy_id) AS vacancies,
       count(r.response_id)         AS responses
FROM employers e
JOIN vacancies v ON v.employer_id = e.employer_id
JOIN responses r ON r.vacancy_id = v.vacancy_id
GROUP BY e.employer_id, e.employer_name
ORDER BY responses DESC, e.employer_name;

-- Вывод:
-- Первый запрос вернул 12 строк, второй 11. Вакансии приходится считать через
-- count(DISTINCT v.vacancy_id), потому что после присоединения откликов строка
-- вакансии повторяется столько раз, сколько у нее откликов, и count(*) считал бы
-- отклики, а не вакансии.
-- Во втором запросе пропала ГринЭнерго, у неё одна вакансия и ноль откликов.
-- Это содержательная потеря, потому что именно такого партнёра HR хочет спросить "почему нет
-- интереса", а INNER JOIN прячет его и оставляет только успешных. При этом он занижает
-- число вакансий у остальных (у ТехноБанка 9 превратились в 8), потому что вакансии
-- без откликов тоже выпадают.
-- Правило: INNER JOIN, когда нужны только объекты у которых есть связь;
-- LEFT JOIN, когда в отчёте должны быть все объекты главной таблицы, включая тех у кого связи нет


-- ============================================================
-- БЛОК Д. Функции и финальный кейс
-- ============================================================

-- ЗАДАНИЕ Д1
-- Запрос: помесячная динамика откликов и конверсия
-- (месяц как дата, условный агрегат, nullif в знаменателе)
SELECT date_trunc('month', created_at)::date AS month,
       count(*) AS responses,
       count(*) FILTER (WHERE status = 'invited') AS invited,
       round(100.0 * count(*) FILTER (WHERE status = 'invited')
                    / nullif(count(*), 0), 1) AS conversion_pct
FROM responses
GROUP BY date_trunc('month', created_at)::date
ORDER BY month;

-- Вывод:
-- Максимальная конверсия была  в июне 2026: 19,5% (23 приглашения на 118 откликов).
-- Объём у июня один из самых больших, но приглашений всего 23, поэтому погрешность
-- составляет около ±7% (истинное значение в интервале 12–27%) и она перекрывает почти все остальные
-- месяцы. К тому же в мае и июле конверсия около 12,6–12,7%, так что июнь больше похож
-- на разовый всплеск и может не иметь значимости, для планирования набора на него
-- ориентироваться нельзя (к тому же данных меньше года, сезонность не проверить).
-- Август (последний) неполный: отклики есть только до 15 августа, их всего 41 против
-- 100+ в полных месяцах, а приглашений 3. Конверсия 7,3% несопоставима с остальными, поэтому
-- в выводы лучше его не брать.


-- ЗАДАНИЕ Д2
-- Запрос: таблица по направлениям (вакансии, отклики, приглашения,
-- откликов на вакансию, конверсия)
SELECT v.professional_role                                 AS direction,
       count(DISTINCT v.vacancy_id)                        AS vacancies,
       count(r.response_id)                                AS responses,
       count(r.response_id) FILTER (WHERE r.status = 'invited') AS invited,
       round(count(r.response_id)::numeric -- count вовзращает целое целое
             / nullif(count(DISTINCT v.vacancy_id), 0), 1) AS responses_per_vacancy,
       round(100.0 * count(r.response_id) FILTER (WHERE r.status = 'invited')
             / nullif(count(r.response_id), 0), 1)         AS conversion_pct
FROM vacancies v
LEFT JOIN responses r ON r.vacancy_id = v.vacancy_id
GROUP BY v.professional_role
ORDER BY vacancies DESC;

-- Письменные ответы:
-- 1. Совпадает ли направление с наибольшим числом вакансий с направлением
--    с наибольшей конверсией?
--    Нет. Больше всего вакансий у «Аналитик данных» (16, конверсия 12,1%), а самая
--    высокая конверсия у «Тестировщик» (35,9%, но всего 7 вакансий).
--
-- 2. Какое направление выбрать и почему (опираясь на два столбца)?
--    «Разработчик». У него 15 вакансий (второе место по числу) и конверсия 17,3%,
--    выше средней (14,6%). При этом откликов на вакансию 9,3 против 19,6 у
--    аналитиков данных, то есть конкуренция примерно вдвое ниже. У тестировщиков
--    конверсия выше, но вакансий всего 7 и откликов 39, лучше не опираться
--    на слишком маленькую выборку.
--
-- 3. Оговорка к выводу:
--    Конверсия и средние показатели по всем откликнувшимся ничего не говорят о шансах конкретного
--    человека: в данных нет опыта и навыков кандидатов, а статус «приглашен» скорее всего не
--    означает оффер.


-- ============================================================
-- БЛОК Е. Со звёздочкой
-- ============================================================

-- ЗАДАНИЕ Е1
-- Исходный запрос (выполнить и посмотреть результат):
SELECT v.professional_role,
count(*) AS vacancies,
sum(v.salary_from) AS total_salary,
count(r.response_id) / count(*) AS responses_per_vacancy
FROM vacancies v
JOIN responses r ON v.vacancy_id = r.vacancy_id
WHERE v.closed_at = NULL
GROUP BY 1;
-- Ошибки:
-- 1. WHERE closed_at = NULL: сравнение с NULL некорректно, поэтому запрос
--    возвращает 0 строк. Нужно использовать IS NULL.
-- 2. count(*) после присоединения таблицы с откликами считает строки соединения (тоесть отклики), а не
--    вакансии. Нужно count(DISTINCT v.vacancy_id).
-- 3. sum(v.salary_from) после того же JOIN суммирует зарплату вакансии столько раз,
--    сколько у неё откликов, в итоге получается очень много.
--    К тому же сумма нижних границ вилок несет мало смысла, лучше использовать среднее avg().
-- 4. count(r.response_id) / count(*). Деление целых чисел отбрасывает дробную часть, 
--    а также в знаменателе стоят отклики, а не вакансии.
--    Нужно привести к numeric, делить на число вакансий и защитить знаменатель через nullif.
-- 5. Внутреннмй JOIN выкидывает вакансии без откликов, а они должны попасть в
--    знаменатель среднего числа откликов. Нужен LEFT JOIN.
--
-- Исправленный запрос:
SELECT v.professional_role,
       count(DISTINCT v.vacancy_id) AS vacancies,
       round(count(r.response_id)::numeric
             / nullif(count(DISTINCT v.vacancy_id), 0), 1) AS responses_per_vacancy
FROM vacancies v
LEFT JOIN responses r ON v.vacancy_id = r.vacancy_id
WHERE v.closed_at IS NULL
GROUP BY 1;

-- В итоге пришлось убрать сумму зарплат,чтобы значительно не менять каркас запроса.
-- Ее можно посчитать отдельным запросом без JOIN.

-- Информация про ЗП отдельно:
SELECT professional_role,
       round(avg(salary_from)) AS avg_salary_from,
       sum(salary_from) AS total_salary_from
FROM vacancies
WHERE closed_at IS NULL
GROUP BY professional_role;

-- Какие два правила из лекции защитили бы от этих ошибок при написании запроса:
-- 1. Пустоту проверяем только через IS NULL
-- 2. Считать обьекты по первичному ключу.
--    (Вакансии считаем через count(DISTINCT v.vacancy_id), а не по строкам после JOIN)
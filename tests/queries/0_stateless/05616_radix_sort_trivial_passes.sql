-- LSD radix sort skips the passes where all keys have the same byte: small numbers in wide types,
-- timestamps from a short period, floats with the same exponent, all equal keys.
-- Compare the radix sort (ORDER BY without LIMIT over blocks of at least 256 rows, groupArraySorted, quantilesGK,
-- quantileTDigest, ASOF JOIN, sorting on INSERT into MergeTree) with `arraySort`, which uses a comparison sort.
-- The keys come in a pseudorandom order, so the presorted data shortcut (`trySort`) does not apply.

SET max_threads = 1;
SET max_block_size = 65536;
SET query_plan_remove_redundant_sorting = 0;

DROP TABLE IF EXISTS t_radix;

CREATE TABLE t_radix
(
    u64_small UInt64,         -- 4 high bytes are zero
    u64_low_byte UInt64,      -- the lowest byte is zero: the first pass is trivial
    u64_const UInt64,         -- all passes are trivial
    u32_small UInt32,
    u16_low_byte UInt16,
    i64_pos Int64,
    i64_neg Int64,
    f64_unit Float64,         -- [1, 2): the same sign and exponent
    f64_neg Float64,
    f64_const Float64,
    f64_int Float64,          -- integers: the low bytes are zero, the exponent differs
    f32_unit Float32,
    bf16_unit BFloat16,
    d64 Decimal64(3),
    dt DateTime('UTC'),
    dt64 DateTime64(3, 'UTC'),
    n_u64 Nullable(UInt64)
) ENGINE = Memory;

INSERT INTO t_radix
SELECT
    intHash64(number) % 4294967296,
    intHash64(number) * 256,
    42,
    toUInt32(intHash64(number) % 65536),
    toUInt16((intHash64(number) % 256) * 256),
    toInt64(intHash64(number) % 1000000),
    -1 - toInt64(intHash64(number) % 1000000),
    1 + (intHash64(number) % 1000000) / 1000000,
    -1 - (intHash64(number) % 1000000) / 1000000,
    1.5,
    toFloat64(intHash64(number) % 1000000),
    toFloat32(1 + (intHash64(number) % 1000000) / 1000000),
    toBFloat16(1 + (intHash64(number) % 128) / 128),
    toDecimal64(intHash64(number) % 100000000, 3),
    toDateTime('2026-01-01 00:00:00', 'UTC') + intHash64(number) % 86400,
    fromUnixTimestamp64Milli(toInt64(1767225600000 + intHash64(number) % 86400000), 'UTC'),
    if(number % 7 = 0, NULL, intHash64(number) % 4294967296)
FROM numbers(10000);

SELECT '-- ORDER BY: ascending, descending';

SELECT 'UInt64 < 2^32',
    (SELECT groupArray(x) FROM (SELECT u64_small AS x FROM t_radix ORDER BY x)) = (SELECT arraySort(groupArray(u64_small)) FROM t_radix),
    (SELECT groupArray(x) FROM (SELECT u64_small AS x FROM t_radix ORDER BY x DESC)) = (SELECT arrayReverseSort(groupArray(u64_small)) FROM t_radix);
SELECT 'UInt64 constant low byte',
    (SELECT groupArray(x) FROM (SELECT u64_low_byte AS x FROM t_radix ORDER BY x)) = (SELECT arraySort(groupArray(u64_low_byte)) FROM t_radix),
    (SELECT groupArray(x) FROM (SELECT u64_low_byte AS x FROM t_radix ORDER BY x DESC)) = (SELECT arrayReverseSort(groupArray(u64_low_byte)) FROM t_radix);
SELECT 'UInt64 all equal',
    (SELECT groupArray(x) FROM (SELECT u64_const AS x FROM t_radix ORDER BY x)) = (SELECT arraySort(groupArray(u64_const)) FROM t_radix),
    (SELECT groupArray(x) FROM (SELECT u64_const AS x FROM t_radix ORDER BY x DESC)) = (SELECT arrayReverseSort(groupArray(u64_const)) FROM t_radix);
SELECT 'UInt32 < 2^16',
    (SELECT groupArray(x) FROM (SELECT u32_small AS x FROM t_radix ORDER BY x)) = (SELECT arraySort(groupArray(u32_small)) FROM t_radix),
    (SELECT groupArray(x) FROM (SELECT u32_small AS x FROM t_radix ORDER BY x DESC)) = (SELECT arrayReverseSort(groupArray(u32_small)) FROM t_radix);
SELECT 'UInt16 constant low byte',
    (SELECT groupArray(x) FROM (SELECT u16_low_byte AS x FROM t_radix ORDER BY x)) = (SELECT arraySort(groupArray(u16_low_byte)) FROM t_radix),
    (SELECT groupArray(x) FROM (SELECT u16_low_byte AS x FROM t_radix ORDER BY x DESC)) = (SELECT arrayReverseSort(groupArray(u16_low_byte)) FROM t_radix);
SELECT 'Int64 small positive',
    (SELECT groupArray(x) FROM (SELECT i64_pos AS x FROM t_radix ORDER BY x)) = (SELECT arraySort(groupArray(i64_pos)) FROM t_radix),
    (SELECT groupArray(x) FROM (SELECT i64_pos AS x FROM t_radix ORDER BY x DESC)) = (SELECT arrayReverseSort(groupArray(i64_pos)) FROM t_radix);
SELECT 'Int64 small negative',
    (SELECT groupArray(x) FROM (SELECT i64_neg AS x FROM t_radix ORDER BY x)) = (SELECT arraySort(groupArray(i64_neg)) FROM t_radix),
    (SELECT groupArray(x) FROM (SELECT i64_neg AS x FROM t_radix ORDER BY x DESC)) = (SELECT arrayReverseSort(groupArray(i64_neg)) FROM t_radix);
SELECT 'Float64 in [1, 2)',
    (SELECT groupArray(x) FROM (SELECT f64_unit AS x FROM t_radix ORDER BY x)) = (SELECT arraySort(groupArray(f64_unit)) FROM t_radix),
    (SELECT groupArray(x) FROM (SELECT f64_unit AS x FROM t_radix ORDER BY x DESC)) = (SELECT arrayReverseSort(groupArray(f64_unit)) FROM t_radix);
SELECT 'Float64 in (-2, -1]',
    (SELECT groupArray(x) FROM (SELECT f64_neg AS x FROM t_radix ORDER BY x)) = (SELECT arraySort(groupArray(f64_neg)) FROM t_radix),
    (SELECT groupArray(x) FROM (SELECT f64_neg AS x FROM t_radix ORDER BY x DESC)) = (SELECT arrayReverseSort(groupArray(f64_neg)) FROM t_radix);
SELECT 'Float64 all equal',
    (SELECT groupArray(x) FROM (SELECT f64_const AS x FROM t_radix ORDER BY x)) = (SELECT arraySort(groupArray(f64_const)) FROM t_radix),
    (SELECT groupArray(x) FROM (SELECT f64_const AS x FROM t_radix ORDER BY x DESC)) = (SELECT arrayReverseSort(groupArray(f64_const)) FROM t_radix);
SELECT 'Float64 integers',
    (SELECT groupArray(x) FROM (SELECT f64_int AS x FROM t_radix ORDER BY x)) = (SELECT arraySort(groupArray(f64_int)) FROM t_radix),
    (SELECT groupArray(x) FROM (SELECT f64_int AS x FROM t_radix ORDER BY x DESC)) = (SELECT arrayReverseSort(groupArray(f64_int)) FROM t_radix);
SELECT 'Float32 in [1, 2)',
    (SELECT groupArray(x) FROM (SELECT f32_unit AS x FROM t_radix ORDER BY x)) = (SELECT arraySort(groupArray(f32_unit)) FROM t_radix),
    (SELECT groupArray(x) FROM (SELECT f32_unit AS x FROM t_radix ORDER BY x DESC)) = (SELECT arrayReverseSort(groupArray(f32_unit)) FROM t_radix);
SELECT 'BFloat16 in [1, 2)',
    (SELECT groupArray(x) FROM (SELECT bf16_unit AS x FROM t_radix ORDER BY x)) = (SELECT arraySort(groupArray(bf16_unit)) FROM t_radix),
    (SELECT groupArray(x) FROM (SELECT bf16_unit AS x FROM t_radix ORDER BY x DESC)) = (SELECT arrayReverseSort(groupArray(bf16_unit)) FROM t_radix);
SELECT 'Decimal64',
    (SELECT groupArray(x) FROM (SELECT d64 AS x FROM t_radix ORDER BY x)) = (SELECT arraySort(groupArray(d64)) FROM t_radix),
    (SELECT groupArray(x) FROM (SELECT d64 AS x FROM t_radix ORDER BY x DESC)) = (SELECT arrayReverseSort(groupArray(d64)) FROM t_radix);
SELECT 'DateTime',
    (SELECT groupArray(x) FROM (SELECT dt AS x FROM t_radix ORDER BY x)) = (SELECT arraySort(groupArray(dt)) FROM t_radix),
    (SELECT groupArray(x) FROM (SELECT dt AS x FROM t_radix ORDER BY x DESC)) = (SELECT arrayReverseSort(groupArray(dt)) FROM t_radix);
SELECT 'DateTime64',
    (SELECT groupArray(x) FROM (SELECT dt64 AS x FROM t_radix ORDER BY x)) = (SELECT arraySort(groupArray(dt64)) FROM t_radix),
    (SELECT groupArray(x) FROM (SELECT dt64 AS x FROM t_radix ORDER BY x DESC)) = (SELECT arrayReverseSort(groupArray(dt64)) FROM t_radix);
-- NULLs go last in both directions; groupArray skips them, so replace them with a value that sorts last.
SELECT 'Nullable(UInt64)',
    (SELECT groupArray(ifNull(x, 18446744073709551615)) FROM (SELECT n_u64 AS x FROM t_radix ORDER BY x)) = (SELECT arraySort(groupArray(ifNull(n_u64, 18446744073709551615))) FROM t_radix),
    (SELECT groupArray(ifNull(x, 0)) FROM (SELECT n_u64 AS x FROM t_radix ORDER BY x DESC)) = (SELECT arrayReverseSort(groupArray(ifNull(n_u64, 0))) FROM t_radix);

SELECT '-- ORDER BY of several columns: radix sort of the equal ranges of the first column';

SELECT 'UInt64 < 2^32',
    (SELECT groupArray((k, x)) FROM (SELECT u64_small % 3 AS k, u64_small AS x FROM t_radix ORDER BY k, x))
        = (SELECT arraySort(groupArray((u64_small % 3, u64_small))) FROM t_radix);
SELECT 'DateTime64 descending',
    (SELECT groupArray((k, x)) FROM (SELECT toUInt8(u32_small % 3) AS k, dt64 AS x FROM t_radix ORDER BY k, x DESC))
        = (SELECT arraySort(p -> (p.1, -toUnixTimestamp64Milli(p.2)), groupArray((toUInt8(u32_small % 3), dt64))) FROM t_radix);
SELECT 'Float64 in [1, 2)',
    (SELECT groupArray((k, x)) FROM (SELECT u64_small % 3 AS k, f64_unit AS x FROM t_radix ORDER BY k, x))
        = (SELECT arraySort(groupArray((u64_small % 3, f64_unit))) FROM t_radix);

SELECT '-- Stable sort on INSERT into MergeTree: the equal keys keep the order of insertion';

DROP TABLE IF EXISTS t_radix_mt;
CREATE TABLE t_radix_mt (x Int64, id UInt64) ENGINE = MergeTree ORDER BY x;
INSERT INTO t_radix_mt SELECT intHash64(number) % 1000, number FROM numbers(10000);
SELECT 'Int64 < 1000', countIf(a != arraySort(a)), sum(length(a))
FROM (SELECT _part, groupArray((x, id)) AS a FROM t_radix_mt GROUP BY _part);
DROP TABLE t_radix_mt;

CREATE TABLE t_radix_mt (x DateTime64(3, 'UTC'), id UInt64) ENGINE = MergeTree ORDER BY x;
INSERT INTO t_radix_mt SELECT fromUnixTimestamp64Milli(toInt64(1767225600000 + intHash64(number) % 1000), 'UTC'), number FROM numbers(10000);
SELECT 'DateTime64 within a second', countIf(a != arraySort(a)), sum(length(a))
FROM (SELECT _part, groupArray((x, id)) AS a FROM t_radix_mt GROUP BY _part);
DROP TABLE t_radix_mt;

-- The second key is constant within each range of equal first keys: all passes of the radix sort of these ranges are trivial.
CREATE TABLE t_radix_mt (k UInt8, c UInt64, id UInt64) ENGINE = MergeTree ORDER BY (k, c);
INSERT INTO t_radix_mt SELECT intHash64(number) % 3 AS k, k * 1000, number FROM numbers(10000);
SELECT 'UInt64 constant within ranges', countIf(a != arraySort(a)), sum(length(a))
FROM (SELECT _part, groupArray((k, c, id)) AS a FROM t_radix_mt GROUP BY _part);
DROP TABLE t_radix_mt;

SELECT '-- groupArraySorted';

SELECT 'UInt64 < 2^32', groupArraySorted(2000000)(u64_small) = arraySort(groupArray(u64_small)) FROM t_radix;
SELECT 'Int64 small negative', groupArraySorted(2000000)(i64_neg) = arraySort(groupArray(i64_neg)) FROM t_radix;
SELECT 'Float64 in [1, 2)', groupArraySorted(2000000)(f64_unit) = arraySort(groupArray(f64_unit)) FROM t_radix;
SELECT 'Float64 in (-2, -1]', groupArraySorted(2000000)(f64_neg) = arraySort(groupArray(f64_neg)) FROM t_radix;
SELECT 'Float64 all equal', groupArraySorted(2000000)(f64_const) = arraySort(groupArray(f64_const)) FROM t_radix;
SELECT 'Float64 integers', groupArraySorted(2000000)(f64_int) = arraySort(groupArray(f64_int)) FROM t_radix;
SELECT 'Float32 in [1, 2)', groupArraySorted(2000000)(f32_unit) = arraySort(groupArray(f32_unit)) FROM t_radix;
SELECT 'BFloat16 in [1, 2)', groupArraySorted(2000000)(bf16_unit) = arraySort(groupArray(bf16_unit)) FROM t_radix;
SELECT 'Int128', groupArraySorted(2000000)(toInt128(i64_neg)) = arraySort(groupArray(toInt128(i64_neg))) FROM t_radix;
SELECT 'UInt256', groupArraySorted(2000000)(toUInt256(u64_small)) = arraySort(groupArray(toUInt256(u64_small))) FROM t_radix;
-- NaNs are moved to the end before sorting, so the radix sort gets an empty array.
SELECT 'only NaN', length(a), arrayAll(x -> isNaN(x), a) FROM (SELECT groupArraySorted(2000000)(nan + number) AS a FROM numbers(1000));

SELECT '-- quantilesGK keeps the minimum and the maximum';

SELECT 'UInt64 < 2^32', quantilesGK(1000, 0, 1)(u64_small) = [min(u64_small), max(u64_small)] FROM t_radix;
SELECT 'Float64 in [1, 2)', quantilesGK(1000, 0, 1)(f64_unit) = [min(f64_unit), max(f64_unit)] FROM t_radix;
SELECT 'Float64 in (-2, -1]', quantilesGK(1000, 0, 1)(f64_neg) = [min(f64_neg), max(f64_neg)] FROM t_radix;

SELECT '-- quantileTDigest';

SELECT 'Float64 all equal', quantileTDigest(0.5)(f64_const) FROM t_radix;
SELECT 'Float64 in [1, 2)', quantileTDigest(0.5)(f64_unit) BETWEEN 1 AND 2 FROM t_radix;
SELECT 'Float64 in (-2, -1]', quantileTDigest(0.5)(f64_neg) BETWEEN -2 AND -1 FROM t_radix;

SELECT '-- ASOF JOIN with more than 256 rows for a key';

DROP TABLE IF EXISTS t_radix_asof;
CREATE TABLE t_radix_asof (k UInt8, t UInt64, v UInt64) ENGINE = Memory;
INSERT INTO t_radix_asof SELECT 1, number * 10, number FROM numbers(1000) ORDER BY intHash64(number);
SELECT 'UInt64', count(), countIf(r.t = intDiv(l.t, 10) * 10), countIf(r.v = intDiv(l.t, 10))
FROM (SELECT toUInt8(1) AS k, number * 7 AS t FROM numbers(1400)) AS l
ASOF JOIN t_radix_asof AS r ON l.k = r.k AND l.t >= r.t;
DROP TABLE t_radix_asof;

CREATE TABLE t_radix_asof (k UInt8, t DateTime64(3, 'UTC'), v UInt64) ENGINE = Memory;
INSERT INTO t_radix_asof SELECT 1, fromUnixTimestamp64Milli(toInt64(1767225600000 + number * 10), 'UTC'), number FROM numbers(1000) ORDER BY intHash64(number);
SELECT 'DateTime64', count(), countIf(r.v = intDiv(toUnixTimestamp64Milli(l.t) - 1767225600000, 10))
FROM (SELECT toUInt8(1) AS k, fromUnixTimestamp64Milli(toInt64(1767225600000 + number * 7), 'UTC') AS t FROM numbers(1400)) AS l
ASOF JOIN t_radix_asof AS r ON l.k = r.k AND l.t >= r.t;
DROP TABLE t_radix_asof;

DROP TABLE t_radix;

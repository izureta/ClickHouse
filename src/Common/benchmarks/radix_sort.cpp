#include <Columns/ColumnsNumber.h>
#include <DataTypes/DataTypesNumber.h>
#include <Functions/FunctionHelpers.h>
#include <Storages/StorageGenerateRandom.h>
#include <benchmark/benchmark.h>

using namespace DB;

static void BM_RadixSort_UInt8(benchmark::State & state)
{
    pcg64 rng;
    UInt64 limit = DEFAULT_BLOCK_SIZE;
    auto type = std::make_shared<DataTypeUInt8>();
    auto column = fillColumnWithRandomData(type, limit, 0, 0, rng);

    for (auto _ [[maybe_unused]] : state)
    {
        IColumn::Permutation res;
        column->getPermutation(IColumn::PermutationSortDirection::Ascending, IColumn::PermutationSortStability::Unstable, 0, 0, res);
        benchmark::DoNotOptimize(res);
    }
}

static void BM_RadixSort_Int16(benchmark::State & state)
{
    pcg64 rng;
    UInt64 limit = DEFAULT_BLOCK_SIZE;
    auto type = std::make_shared<DataTypeInt16>();
    auto column = fillColumnWithRandomData(type, limit, 0, 0, rng);

    for (auto _ [[maybe_unused]] : state)
    {
        IColumn::Permutation res;
        column->getPermutation(IColumn::PermutationSortDirection::Ascending, IColumn::PermutationSortStability::Unstable, 0, 0, res);
        benchmark::DoNotOptimize(res);
    }
}

static void BM_RadixSort_Int32(benchmark::State & state)
{
    pcg64 rng;
    UInt64 limit = DEFAULT_BLOCK_SIZE;
    auto type = std::make_shared<DataTypeInt32>();
    auto column = fillColumnWithRandomData(type, limit, 0, 0, rng);

    for (auto _ [[maybe_unused]] : state)
    {
        IColumn::Permutation res;
        column->getPermutation(IColumn::PermutationSortDirection::Ascending, IColumn::PermutationSortStability::Unstable, 0, 0, res);
        benchmark::DoNotOptimize(res);
    }
}

static void BM_RadixSort_UInt64(benchmark::State & state)
{
    pcg64 rng;
    UInt64 limit = DEFAULT_BLOCK_SIZE;
    auto type = std::make_shared<DataTypeUInt64>();
    auto column = fillColumnWithRandomData(type, limit, 0, 0, rng);

    for (auto _ [[maybe_unused]] : state)
    {
        IColumn::Permutation res;
        column->getPermutation(IColumn::PermutationSortDirection::Ascending, IColumn::PermutationSortStability::Unstable, 0, 0, res);
        benchmark::DoNotOptimize(res);
    }
}

/// The data where some passes of LSD radix sort are trivial: all elements have the same value of the bit range.
template <typename T, typename Generator>
static void benchmarkRadixSortOf(benchmark::State & state, Generator generate)
{
    pcg64 rng;
    auto column = ColumnVector<T>::create();
    auto & data = column->getData();
    data.resize(DEFAULT_BLOCK_SIZE);
    for (auto & value : data)
        value = generate(rng);

    for (auto _ [[maybe_unused]] : state)
    {
        IColumn::Permutation res;
        column->getPermutation(IColumn::PermutationSortDirection::Ascending, IColumn::PermutationSortStability::Unstable, 0, 0, res);
        benchmark::DoNotOptimize(res);
    }
}

static void BM_RadixSort_UInt64_Below2Pow32(benchmark::State & state)
{
    benchmarkRadixSortOf<UInt64>(state, [](pcg64 & rng) { return static_cast<UInt64>(static_cast<UInt32>(rng())); });
}

static void BM_RadixSort_Int64_TimestampsOfOneDay(benchmark::State & state)
{
    /// Milliseconds since epoch, as in `DateTime64(3)`.
    benchmarkRadixSortOf<Int64>(state, [](pcg64 & rng) { return static_cast<Int64>(1767225600000 + rng() % 86400000); });
}

static void BM_RadixSort_Float64_Integers(benchmark::State & state)
{
    benchmarkRadixSortOf<Float64>(state, [](pcg64 & rng) { return static_cast<Float64>(rng() % 1000000); });
}

static void BM_RadixSort_UInt64_AllEqual(benchmark::State & state)
{
    benchmarkRadixSortOf<UInt64>(state, [](pcg64 &) { return UInt64(42); });
}

BENCHMARK(BM_RadixSort_UInt8);
BENCHMARK(BM_RadixSort_Int16);
BENCHMARK(BM_RadixSort_Int32);
BENCHMARK(BM_RadixSort_UInt64);
BENCHMARK(BM_RadixSort_UInt64_Below2Pow32);
BENCHMARK(BM_RadixSort_Int64_TimestampsOfOneDay);
BENCHMARK(BM_RadixSort_Float64_Integers);
BENCHMARK(BM_RadixSort_UInt64_AllEqual);

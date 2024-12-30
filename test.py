from datetime import timedelta, datetime, UTC


def original_dutch_auction(block_timestamp, lido_rebase_time):
    """Simulate the original Dutch auction logic."""
    time = (block_timestamp - lido_rebase_time) % (24 * 60 * 60)
    return time
    # if time < 30 * 60:  # 30 minutes
    #     return 10_000
    # return 10_000 - ((time // (30 * 60)) - 1) * 100


def improved_dutch_auction(block_timestamp, lido_rebase_time):
    """Simulate the improved Dutch auction logic."""
    time = block_timestamp % (24 * 60 * 60)
    if time < lido_rebase_time:
        return 10_000
    time_passed_after_rebase = time - lido_rebase_time
    return time_passed_after_rebase
    # if time_passed_after_rebase < 30 * 60:  # 30 minutes
    #     return 10_000
    # return 10_000 - (time_passed_after_rebase // (30 * 60)) * 100


# Simulating over a 24-hour period
current_time = datetime(2024, 1, 1, 12, 0, 0,tzinfo=UTC)
rebase_time = 12 * 60 * 60  # 12 PM UTC in seconds
block_timestamp = int(current_time.timestamp())

result1 = original_dutch_auction(block_timestamp, rebase_time)
result2 = improved_dutch_auction(block_timestamp, rebase_time)
print(
    "time passed after rebase original",
    datetime.fromtimestamp(result1, UTC).strftime("%H:%M:%S"),
)
print(
    "time passed after rebase improved",
    datetime.fromtimestamp(result2, UTC).strftime("%H:%M:%S"),
)

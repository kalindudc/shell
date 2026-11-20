def mean(values):
    return sum(values) / len(values)


def median(values):
    if not values:
        raise ValueError("median requires at least one value")
    ordered = sorted(values)
    return ordered[len(ordered) // 2]

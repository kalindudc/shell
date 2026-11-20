import unittest

from calc import mean, median


class MeanTests(unittest.TestCase):
    def test_empty_mean(self):
        result = mean([])
        self.assertIsInstance(result, float)
        self.assertEqual(result, 0.0)

    def test_nonempty_mean(self):
        self.assertEqual(mean([2, -2, 9]), 3.0)


class MedianTests(unittest.TestCase):
    def test_even_median(self):
        self.assertEqual(median([8, 2, 5, 1]), 3.5)

    def test_odd_median(self):
        self.assertEqual(median([7, 1, 3]), 3)

    def test_empty_median(self):
        with self.assertRaises(ValueError):
            median([])


if __name__ == "__main__":
    unittest.main()


def process_numbers(numbers):
    results = []
    for num in numbers:
        results.append(num * 2)
    return results

def filter_evens(numbers):
    evens = []
    for num in numbers:
        if num % 2 == 0:
            evens.append(num)
    return evens

def get_squares(numbers):
    squares = []
    for x in numbers:
        squares.append(x ** 2)
    return squares


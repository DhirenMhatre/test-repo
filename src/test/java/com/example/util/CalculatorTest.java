package com.example.util;

import com.example.util.Calculator;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("Calculator Tests")
class CalculatorTest {

    private Calculator calculator;

    @BeforeEach
    void setUp() {
        calculator = new Calculator();
    }

    @AfterEach
    void tearDown() {
        calculator = null;
    }

    @Test
    @DisplayName("Should create instance successfully")
    void testConstructor() {
        assertNotNull(calculator);
    }

    // add tests

    @Test
    @DisplayName("add: two positive numbers")
    void testAdd_PositiveNumbers() {
        assertEquals(5, calculator.add(2, 3));
        assertEquals(100, calculator.add(40, 60));
    }

    @Test
    @DisplayName("add: with zero as operand")
    void testAdd_WithZero() {
        assertEquals(5, calculator.add(5, 0));
        assertEquals(5, calculator.add(0, 5));
        assertEquals(0, calculator.add(0, 0));
    }

    @Test
    @DisplayName("add: negative numbers")
    void testAdd_NegativeNumbers() {
        assertEquals(-5, calculator.add(-2, -3));
        assertEquals(0, calculator.add(-5, 5));
        assertEquals(-10, calculator.add(-4, -6));
    }

    @Test
    @DisplayName("add: mixed signs")
    void testAdd_MixedSigns() {
        assertEquals(2, calculator.add(5, -3));
        assertEquals(-8, calculator.add(-5, -3));
        assertEquals(-2, calculator.add(-5, 3));
    }

    @Test
    @DisplayName("add: integer overflow wraps around")
    void testAdd_IntegerOverflow() {
        int a = Integer.MAX_VALUE;
        int b = 1;
        int result = calculator.add(a, b);
        assertEquals(Integer.MIN_VALUE, result);
    }

    // subtract tests

    @Test
    @DisplayName("subtract: two positive numbers")
    void testSubtract_PositiveNumbers() {
        assertEquals(2, calculator.subtract(5, 3));
        assertEquals(0, calculator.subtract(100, 100));
    }

    @Test
    @DisplayName("subtract: with zero")
    void testSubtract_WithZero() {
        assertEquals(5, calculator.subtract(5, 0));
        assertEquals(-5, calculator.subtract(0, 5));
        assertEquals(0, calculator.subtract(0, 0));
    }

    @Test
    @DisplayName("subtract: negative numbers")
    void testSubtract_NegativeNumbers() {
        assertEquals(-2, calculator.subtract(-5, -3));
        assertEquals(8, calculator.subtract(5, -3));
        assertEquals(-8, calculator.subtract(-5, 3));
    }

    @Test
    @DisplayName("subtract: integer underflow wraps around")
    void testSubtract_IntegerUnderflow() {
        int a = Integer.MIN_VALUE;
        int b = 1;
        int result = calculator.subtract(a, b);
        assertEquals(Integer.MAX_VALUE, result);
    }

    // multiply tests

    @Test
    @DisplayName("multiply: two positive numbers")
    void testMultiply_PositiveNumbers() {
        assertEquals(15, calculator.multiply(3, 5));
        assertEquals(0, calculator.multiply(0, 12345)); // also checks zero
    }

    @Test
    @DisplayName("multiply: by zero")
    void testMultiply_ByZero() {
        assertEquals(0, calculator.multiply(7, 0));
        assertEquals(0, calculator.multiply(0, 7));
        assertEquals(0, calculator.multiply(0, 0));
    }

    @Test
    @DisplayName("multiply: by one (identity)")
    void testMultiply_ByOne() {
        assertEquals(9, calculator.multiply(9, 1));
        assertEquals(9, calculator.multiply(1, 9));
        assertEquals(-9, calculator.multiply(-9, 1));
    }

    @Test
    @DisplayName("multiply: negatives and mixed signs")
    void testMultiply_Negatives() {
        assertEquals(12, calculator.multiply(-3, -4));
        assertEquals(-12, calculator.multiply(-3, 4));
        assertEquals(-12, calculator.multiply(3, -4));
    }

    @Test
    @DisplayName("multiply: overflow behavior for large operands")
    void testMultiply_Overflow() {
        int a = 50_000;
        int b = 50_000;
        int expected = a * b; // intentional overflow using int arithmetic
        assertEquals(expected, calculator.multiply(a, b));
    }

    @Test
    @DisplayName("multiply: MIN_VALUE * -1 overflows to MIN_VALUE")
    void testMultiply_MinValueTimesMinusOne() {
        int result = calculator.multiply(Integer.MIN_VALUE, -1);
        assertEquals(Integer.MIN_VALUE, result);
    }

    // divide tests

    @Test
    @DisplayName("divide: exact division yields integer as double")
    void testDivide_Exact() {
        double result = calculator.divide(10, 5);
        assertEquals(2.0, result, 1e-9);
    }

    @Test
    @DisplayName("divide: non-integer result")
    void testDivide_NonIntegerResult() {
        double result = calculator.divide(1, 2);
        assertEquals(0.5, result, 1e-9);
    }

    @Test
    @DisplayName("divide: negative dividend")
    void testDivide_NegativeDividend() {
        double result = calculator.divide(-9, 2);
        assertEquals(-4.5, result, 1e-9);
    }

    @Test
    @DisplayName("divide: negative divisor")
    void testDivide_NegativeDivisor() {
        double result = calculator.divide(9, -2);
        assertEquals(-4.5, result, 1e-9);
    }

    @Test
    @DisplayName("divide: both negative")
    void testDivide_BothNegative() {
        double result = calculator.divide(-9, -3);
        assertEquals(3.0, result, 1e-9);
    }

    @Test
    @DisplayName("divide: zero dividend")
    void testDivide_ZeroDividend() {
        double result = calculator.divide(0, 5);
        assertEquals(0.0, result, 1e-9);
    }

    @Test
    @DisplayName("divide: by zero throws IllegalArgumentException with message")
    void testDivide_ByZero_ThrowsException() {
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () -> calculator.divide(10, 0));
        assertEquals("Cannot divide by zero", ex.getMessage());
    }
}
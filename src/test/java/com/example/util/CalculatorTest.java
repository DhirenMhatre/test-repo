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

    // add

    @Test
    @DisplayName("add: two positive numbers")
    void testAdd_PositiveNumbers() {
        int result = calculator.add(2, 3);
        assertEquals(5, result);
    }

    @Test
    @DisplayName("add: with zero on either side")
    void testAdd_WithZero() {
        assertEquals(5, calculator.add(5, 0));
        assertEquals(5, calculator.add(0, 5));
    }

    @Test
    @DisplayName("add: negative numbers and mixed signs")
    void testAdd_NegativeNumbers() {
        assertEquals(-5, calculator.add(-2, -3));
        assertEquals(0, calculator.add(-5, 5));
        assertEquals(-1, calculator.add(4, -5));
    }

    @Test
    @DisplayName("add: integer overflow wraps around")
    void testAdd_Overflow() {
        int expected = Integer.MAX_VALUE + 1; // wraps to Integer.MIN_VALUE
        int result = calculator.add(Integer.MAX_VALUE, 1);
        assertEquals(expected, result);
    }

    // subtract

    @Test
    @DisplayName("subtract: basic subtraction")
    void testSubtract_Basic() {
        assertEquals(2, calculator.subtract(5, 3));
    }

    @Test
    @DisplayName("subtract: result is negative")
    void testSubtract_ToNegative() {
        assertEquals(-2, calculator.subtract(3, 5));
    }

    @Test
    @DisplayName("subtract: with zero on either side")
    void testSubtract_WithZero() {
        assertEquals(7, calculator.subtract(7, 0));
        assertEquals(-7, calculator.subtract(0, 7));
    }

    @Test
    @DisplayName("subtract: subtracting negative equals addition")
    void testSubtract_NegativeOperand() {
        assertEquals(9, calculator.subtract(4, -5));
        assertEquals(-1, calculator.subtract(-6, -5));
    }

    @Test
    @DisplayName("subtract: integer underflow wraps around")
    void testSubtract_Underflow() {
        int expected = Integer.MIN_VALUE - 1; // wraps to Integer.MAX_VALUE
        int result = calculator.subtract(Integer.MIN_VALUE, 1);
        assertEquals(expected, result);
    }

    // multiply

    @Test
    @DisplayName("multiply: two positive numbers")
    void testMultiply_PositiveNumbers() {
        assertEquals(15, calculator.multiply(3, 5));
    }

    @Test
    @DisplayName("multiply: with zero")
    void testMultiply_WithZero() {
        assertEquals(0, calculator.multiply(0, 5));
        assertEquals(0, calculator.multiply(5, 0));
    }

    @Test
    @DisplayName("multiply: negatives and sign handling")
    void testMultiply_Negatives() {
        assertEquals(-12, calculator.multiply(-4, 3));
        assertEquals(12, calculator.multiply(-4, -3));
    }

    @Test
    @DisplayName("multiply: integer overflow wraps around")
    void testMultiply_Overflow() {
        int expected = Integer.MAX_VALUE * 2; // wraps
        int result = calculator.multiply(Integer.MAX_VALUE, 2);
        assertEquals(expected, result);
    }

    // divide

    @Test
    @DisplayName("divide: exact division returns double")
    void testDivide_Exact() {
        double result = calculator.divide(10, 5);
        assertEquals(2.0, result, 1e-9);
    }

    @Test
    @DisplayName("divide: non-integer division produces fraction")
    void testDivide_NonInteger() {
        double result = calculator.divide(7, 2);
        assertEquals(3.5, result, 1e-9);
    }

    @Test
    @DisplayName("divide: negative results and sign handling")
    void testDivide_Negatives() {
        assertEquals(-3.0, calculator.divide(-9, 3), 1e-9);
        assertEquals(-3.0, calculator.divide(9, -3), 1e-9);
        assertEquals(3.0, calculator.divide(-9, -3), 1e-9);
    }

    @Test
    @DisplayName("divide: zero numerator yields 0.0")
    void testDivide_ZeroNumerator() {
        assertEquals(0.0, calculator.divide(0, 7), 1e-9);
        assertEquals(0.0, calculator.divide(0, -7), 1e-9);
    }

    @Test
    @DisplayName("divide: division by zero throws IllegalArgumentException")
    void testDivide_ByZero_ThrowsException() {
        assertThrows(IllegalArgumentException.class, () -> calculator.divide(10, 0));
    }

    @Test
    @DisplayName("divide: division by zero error message is descriptive")
    void testDivide_ByZero_Message() {
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () -> calculator.divide(1, 0));
        assertEquals("Cannot divide by zero", ex.getMessage());
    }

    @Test
    @DisplayName("divide: MIN_VALUE divided by -1 is represented correctly as double")
    void testDivide_MinIntByMinusOne() {
        double result = calculator.divide(Integer.MIN_VALUE, -1);
        assertEquals(2147483648.0, result, 1e-9);
    }
}
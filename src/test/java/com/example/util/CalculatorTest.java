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
        int result = calculator.add(2, 3);
        assertEquals(5, result);
    }

    @Test
    @DisplayName("add: with zero")
    void testAdd_WithZero() {
        assertEquals(5, calculator.add(5, 0));
        assertEquals(5, calculator.add(0, 5));
    }

    @Test
    @DisplayName("add: negative numbers and mixed signs")
    void testAdd_NegativeNumbers() {
        assertEquals(-5, calculator.add(-2, -3));
        assertEquals(0, calculator.add(-5, 5));
        assertEquals(-2, calculator.add(3, -5));
    }

    @Test
    @DisplayName("add: boundary overflow wraps around")
    void testAdd_BoundaryOverflow() {
        int result = calculator.add(Integer.MAX_VALUE, 1);
        assertEquals(Integer.MIN_VALUE, result);
    }

    // subtract tests
    @Test
    @DisplayName("subtract: positive numbers")
    void testSubtract_PositiveNumbers() {
        assertEquals(2, calculator.subtract(5, 3));
    }

    @Test
    @DisplayName("subtract: result negative")
    void testSubtract_ResultNegative() {
        assertEquals(-4, calculator.subtract(1, 5));
    }

    @Test
    @DisplayName("subtract: with zero")
    void testSubtract_WithZero() {
        assertEquals(7, calculator.subtract(7, 0));
        assertEquals(-7, calculator.subtract(0, 7));
    }

    @Test
    @DisplayName("subtract: boundary overflow wraps around")
    void testSubtract_BoundaryOverflow() {
        int result = calculator.subtract(Integer.MIN_VALUE, 1);
        assertEquals(Integer.MAX_VALUE, result);
    }

    // multiply tests
    @Test
    @DisplayName("multiply: positive numbers")
    void testMultiply_PositiveNumbers() {
        assertEquals(15, calculator.multiply(3, 5));
    }

    @Test
    @DisplayName("multiply: by zero")
    void testMultiply_ByZero() {
        assertEquals(0, calculator.multiply(10, 0));
        assertEquals(0, calculator.multiply(0, 10));
    }

    @Test
    @DisplayName("multiply: negative numbers and signs")
    void testMultiply_NegativeNumbers() {
        assertEquals(-12, calculator.multiply(-3, 4));
        assertEquals(-12, calculator.multiply(3, -4));
        assertEquals(12, calculator.multiply(-3, -4));
    }

    @Test
    @DisplayName("multiply: by -1")
    void testMultiply_ByNegativeOne() {
        assertEquals(-7, calculator.multiply(7, -1));
        assertEquals(7, calculator.multiply(-7, -1));
    }

    @Test
    @DisplayName("multiply: boundary overflow wraps around")
    void testMultiply_BoundaryOverflow() {
        int result = calculator.multiply(Integer.MAX_VALUE, 2);
        assertEquals(-2, result);
    }

    // divide tests
    @Test
    @DisplayName("divide: exact division")
    void testDivide_Exact() {
        double result = calculator.divide(10, 5);
        assertEquals(2.0, result, 1e-10);
    }

    @Test
    @DisplayName("divide: non-exact division (decimal result)")
    void testDivide_NonExact() {
        double result = calculator.divide(1, 4);
        assertEquals(0.25, result, 1e-10);
    }

    @Test
    @DisplayName("divide: negative result")
    void testDivide_NegativeResult() {
        double result1 = calculator.divide(-9, 2);
        double result2 = calculator.divide(9, -2);
        assertEquals(-4.5, result1, 1e-10);
        assertEquals(-4.5, result2, 1e-10);
    }

    @Test
    @DisplayName("divide: zero numerator")
    void testDivide_ZeroNumerator() {
        double result = calculator.divide(0, 7);
        assertEquals(0.0, result, 1e-10);
    }

    @Test
    @DisplayName("divide: by zero throws IllegalArgumentException with message")
    void testDivide_ByZero_ThrowsException() {
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () -> calculator.divide(10, 0));
        assertEquals("Cannot divide by zero", ex.getMessage());
    }
}
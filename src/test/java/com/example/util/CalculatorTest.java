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

    // Addition tests

    @Test
    @DisplayName("add: Should add two positive numbers")
    void testAdd_PositiveNumbers() {
        int result = calculator.add(2, 3);
        assertEquals(5, result);
    }

    @Test
    @DisplayName("add: Should add with zero (identity)")
    void testAdd_WithZero() {
        assertEquals(5, calculator.add(5, 0));
        assertEquals(5, calculator.add(0, 5));
        assertEquals(0, calculator.add(0, 0));
    }

    @Test
    @DisplayName("add: Should add negative numbers and mixed signs")
    void testAdd_NegativeNumbers() {
        assertEquals(-5, calculator.add(-2, -3));
        assertEquals(0, calculator.add(-5, 5));
        assertEquals(3, calculator.add(5, -2));
    }

    @Test
    @DisplayName("add: Should wrap on integer overflow")
    void testAdd_IntegerOverflowWrapsAround() {
        assertEquals(Integer.MIN_VALUE, calculator.add(Integer.MAX_VALUE, 1));
        assertEquals(Integer.MAX_VALUE, calculator.add(Integer.MIN_VALUE, -1));
    }

    // Subtraction tests

    @Test
    @DisplayName("subtract: Should subtract two positive numbers")
    void testSubtract_PositiveNumbers() {
        assertEquals(2, calculator.subtract(5, 3));
        assertEquals(0, calculator.subtract(5, 5));
    }

    @Test
    @DisplayName("subtract: Should handle zero")
    void testSubtract_WithZero() {
        assertEquals(5, calculator.subtract(5, 0));
        assertEquals(-5, calculator.subtract(0, 5));
        assertEquals(0, calculator.subtract(0, 0));
    }

    @Test
    @DisplayName("subtract: Should handle negative numbers and mixed signs")
    void testSubtract_NegativeNumbers() {
        assertEquals(2, calculator.subtract(-3, -5));
        assertEquals(-8, calculator.subtract(-3, 5));
        assertEquals(8, calculator.subtract(5, -3));
    }

    @Test
    @DisplayName("subtract: Should wrap on integer underflow")
    void testSubtract_IntegerUnderflowWrapsAround() {
        assertEquals(Integer.MAX_VALUE, calculator.subtract(Integer.MIN_VALUE, 1));
        assertEquals(Integer.MIN_VALUE, calculator.subtract(Integer.MAX_VALUE, -1));
    }

    // Multiplication tests

    @Test
    @DisplayName("multiply: Should multiply positive numbers")
    void testMultiply_PositiveNumbers() {
        assertEquals(15, calculator.multiply(3, 5));
        assertEquals(1, calculator.multiply(1, 1));
    }

    @Test
    @DisplayName("multiply: Should handle zero (annihilator)")
    void testMultiply_WithZero() {
        assertEquals(0, calculator.multiply(0, 5));
        assertEquals(0, calculator.multiply(5, 0));
        assertEquals(0, calculator.multiply(0, 0));
    }

    @Test
    @DisplayName("multiply: Should handle identity and sign changes")
    void testMultiply_WithOneAndMinusOne() {
        assertEquals(7, calculator.multiply(7, 1));
        assertEquals(-7, calculator.multiply(7, -1));
        assertEquals(7, calculator.multiply(-7, -1));
    }

    @Test
    @DisplayName("multiply: Should handle negative numbers")
    void testMultiply_NegativeNumbers() {
        assertEquals(15, calculator.multiply(-3, -5));
        assertEquals(-15, calculator.multiply(-3, 5));
        assertEquals(-15, calculator.multiply(3, -5));
    }

    @Test
    @DisplayName("multiply: Should wrap on integer overflow")
    void testMultiply_IntegerOverflowWrapsAround() {
        assertEquals(-2, calculator.multiply(Integer.MAX_VALUE, 2));
        assertEquals(Integer.MIN_VALUE, calculator.multiply(Integer.MIN_VALUE, -1));
    }

    // Division tests

    @Test
    @DisplayName("divide: Should divide exactly for divisible numbers")
    void testDivide_ExactDivision() {
        double result = calculator.divide(10, 5);
        assertEquals(2.0, result);
    }

    @Test
    @DisplayName("divide: Should produce fractional result")
    void testDivide_FractionalResult() {
        double result1 = calculator.divide(1, 2);
        assertEquals(0.5, result1, 1e-12);

        double result2 = calculator.divide(3, 2);
        assertEquals(1.5, result2, 1e-12);
    }

    @Test
    @DisplayName("divide: Should handle negative numbers")
    void testDivide_NegativeNumbers() {
        assertEquals(-4.5, calculator.divide(9, -2), 1e-12);
        assertEquals(3.0, calculator.divide(-9, -3), 1e-12);
        assertEquals(-3.0, calculator.divide(-9, 3), 1e-12);
    }

    @Test
    @DisplayName("divide: Should return zero when numerator is zero")
    void testDivide_ZeroNumerator() {
        assertEquals(0.0, calculator.divide(0, 3), 0.0);
        assertEquals(0.0, calculator.divide(0, -3), 0.0);
    }

    @Test
    @DisplayName("divide: Should handle boundary values with double result")
    void testDivide_BoundaryValuesToDouble() {
        double result = calculator.divide(Integer.MIN_VALUE, -1);
        assertEquals(2147483648.0, result, 0.0);

        double result2 = calculator.divide(Integer.MAX_VALUE, 1);
        assertEquals((double) Integer.MAX_VALUE, result2, 0.0);
    }

    @Test
    @DisplayName("divide: Should handle non-terminating decimal with tolerance")
    void testDivide_NonTerminatingDecimal() {
        double result = calculator.divide(2, 3);
        assertEquals(0.6666666666666666, result, 1e-12);
    }

    @Test
    @DisplayName("divide: Should throw IllegalArgumentException for division by zero")
    void testDivide_ByZero_ThrowsIllegalArgumentException() {
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () -> calculator.divide(10, 0));
        assertTrue(ex.getMessage().contains("Cannot divide by zero"));
    }
}
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

    // Add tests

    @Test
    @DisplayName("Should add two positive numbers")
    void testAdd_PositiveNumbers() {
        assertEquals(9, calculator.add(4, 5));
    }

    @Test
    @DisplayName("Should add with zero (both orders)")
    void testAdd_WithZero() {
        assertEquals(7, calculator.add(7, 0));
        assertEquals(7, calculator.add(0, 7));
    }

    @Test
    @DisplayName("Should add negative numbers and mixed signs")
    void testAdd_NegativeNumbers() {
        assertEquals(-5, calculator.add(-2, -3));
        assertEquals(0, calculator.add(-5, 5));
        assertEquals(-10, calculator.add(-7, -3));
        assertEquals(2, calculator.add(-3, 5));
    }

    @Test
    @DisplayName("Should handle integer overflow when adding (MAX_VALUE + 1 -> MIN_VALUE)")
    void testAdd_Overflow_MaxPlusOne() {
        assertEquals(Integer.MIN_VALUE, calculator.add(Integer.MAX_VALUE, 1));
    }

    @Test
    @DisplayName("Should handle integer overflow when adding (MIN_VALUE + -1 -> MAX_VALUE)")
    void testAdd_Overflow_MinMinusOne() {
        assertEquals(Integer.MAX_VALUE, calculator.add(Integer.MIN_VALUE, -1));
    }

    // Subtract tests

    @Test
    @DisplayName("Should subtract to produce a positive result")
    void testSubtract_PositiveResult() {
        assertEquals(7, calculator.subtract(10, 3));
    }

    @Test
    @DisplayName("Should subtract with zero correctly")
    void testSubtract_WithZero() {
        assertEquals(8, calculator.subtract(8, 0));
        assertEquals(-8, calculator.subtract(0, 8));
    }

    @Test
    @DisplayName("Should subtract negative numbers (equivalent to addition)")
    void testSubtract_WithNegativeOperands() {
        assertEquals(8, calculator.subtract(5, -3));
        assertEquals(-2, calculator.subtract(-5, -3));
    }

    @Test
    @DisplayName("Should handle integer overflow when subtracting (MIN_VALUE - 1 -> MAX_VALUE)")
    void testSubtract_Overflow_MinMinusOne() {
        assertEquals(Integer.MAX_VALUE, calculator.subtract(Integer.MIN_VALUE, 1));
    }

    @Test
    @DisplayName("Should handle integer overflow when subtracting (MAX_VALUE - (-1) -> MIN_VALUE)")
    void testSubtract_Overflow_MaxMinusNegOne() {
        assertEquals(Integer.MIN_VALUE, calculator.subtract(Integer.MAX_VALUE, -1));
    }

    // Multiply tests

    @Test
    @DisplayName("Should multiply two positive numbers")
    void testMultiply_PositiveNumbers() {
        assertEquals(20, calculator.multiply(4, 5));
    }

    @Test
    @DisplayName("Should multiply by zero")
    void testMultiply_ByZero() {
        assertEquals(0, calculator.multiply(7, 0));
        assertEquals(0, calculator.multiply(0, 7));
    }

    @Test
    @DisplayName("Should multiply negative and positive numbers")
    void testMultiply_NegativeAndPositive() {
        assertEquals(-21, calculator.multiply(-7, 3));
        assertEquals(-21, calculator.multiply(7, -3));
    }

    @Test
    @DisplayName("Should multiply two negative numbers")
    void testMultiply_TwoNegatives() {
        assertEquals(28, calculator.multiply(-7, -4));
    }

    @Test
    @DisplayName("Should handle integer overflow when multiplying (MAX_VALUE * 2 -> -2)")
    void testMultiply_Overflow_MaxTimesTwo() {
        assertEquals(-2, calculator.multiply(Integer.MAX_VALUE, 2));
    }

    @Test
    @DisplayName("Should handle integer overflow when multiplying (MIN_VALUE * -1 -> MIN_VALUE)")
    void testMultiply_Overflow_MinTimesNegOne() {
        assertEquals(Integer.MIN_VALUE, calculator.multiply(Integer.MIN_VALUE, -1));
    }

    // Divide tests

    @Test
    @DisplayName("Should divide exactly when divisible")
    void testDivide_ExactDivision() {
        assertEquals(2.0, calculator.divide(10, 5), 1e-9);
        assertEquals(3.0, calculator.divide(9, 3), 1e-9);
    }

    @Test
    @DisplayName("Should return non-integer quotient for non-exact division")
    void testDivide_NonIntegerResult() {
        assertEquals(2.5, calculator.divide(5, 2), 1e-9);
        assertEquals(1073741823.5, calculator.divide(Integer.MAX_VALUE, 2), 1e-6);
    }

    @Test
    @DisplayName("Should handle negative division")
    void testDivide_NegativeDivision() {
        assertEquals(-3.0, calculator.divide(-9, 3), 1e-9);
        assertEquals(-3.0, calculator.divide(9, -3), 1e-9);
        assertEquals(3.0, calculator.divide(-9, -3), 1e-9);
    }

    @Test
    @DisplayName("Should return 0.0 when numerator is zero")
    void testDivide_ZeroNumerator() {
        assertEquals(0.0, calculator.divide(0, 5), 1e-9);
        assertEquals(-0.0, calculator.divide(0, -5), 1e-9);
    }

    @Test
    @DisplayName("Should throw IllegalArgumentException for division by zero")
    void testDivide_ByZero_ThrowsException() {
        assertThrows(IllegalArgumentException.class, () -> calculator.divide(10, 0));
    }

    @Test
    @DisplayName("Exception message should be precise for division by zero")
    void testDivide_ByZero_ExceptionMessage() {
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () -> calculator.divide(1, 0));
        assertEquals("Cannot divide by zero", ex.getMessage());
    }
}
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
    @DisplayName("add: Should add two positive numbers")
    void testAdd_PositiveNumbers() {
        int result = calculator.add(2, 3);
        assertEquals(5, result);
    }

    @Test
    @DisplayName("add: Should add with zero")
    void testAdd_WithZero() {
        assertEquals(5, calculator.add(5, 0));
        assertEquals(5, calculator.add(0, 5));
    }

    @Test
    @DisplayName("add: Should add negative numbers")
    void testAdd_NegativeNumbers() {
        assertEquals(-5, calculator.add(-2, -3));
        assertEquals(-10, calculator.add(-5, -5));
    }

    @Test
    @DisplayName("add: Should add mixed sign numbers")
    void testAdd_MixedSigns() {
        assertEquals(0, calculator.add(-5, 5));
        assertEquals(-2, calculator.add(-5, 3));
    }

    @Test
    @DisplayName("add: Should overflow from Integer.MAX_VALUE + 1 to Integer.MIN_VALUE")
    void testAdd_Overflow_MaxPlusOne() {
        assertEquals(Integer.MIN_VALUE, calculator.add(Integer.MAX_VALUE, 1));
    }

    @Test
    @DisplayName("add: Should overflow from Integer.MIN_VALUE + (-1) to Integer.MAX_VALUE")
    void testAdd_Overflow_MinPlusMinusOne() {
        assertEquals(Integer.MAX_VALUE, calculator.add(Integer.MIN_VALUE, -1));
    }

    // subtract tests

    @Test
    @DisplayName("subtract: Should subtract to positive result")
    void testSubtract_PositiveResult() {
        assertEquals(2, calculator.subtract(5, 3));
    }

    @Test
    @DisplayName("subtract: Should subtract to negative result")
    void testSubtract_NegativeResult() {
        assertEquals(-2, calculator.subtract(3, 5));
    }

    @Test
    @DisplayName("subtract: Should subtract with zero correctly")
    void testSubtract_WithZero() {
        assertEquals(7, calculator.subtract(7, 0));
        assertEquals(-7, calculator.subtract(0, 7));
    }

    @Test
    @DisplayName("subtract: Should handle negative operands")
    void testSubtract_NegativeOperands() {
        assertEquals(-2, calculator.subtract(-5, -3));
        assertEquals(-8, calculator.subtract(-5, 3));
        assertEquals(8, calculator.subtract(5, -3));
    }

    @Test
    @DisplayName("subtract: Should overflow from Integer.MAX_VALUE - (-1) to Integer.MIN_VALUE")
    void testSubtract_Overflow_MaxMinusNegativeOne() {
        assertEquals(Integer.MIN_VALUE, calculator.subtract(Integer.MAX_VALUE, -1));
    }

    @Test
    @DisplayName("subtract: Should overflow from Integer.MIN_VALUE - 1 to Integer.MAX_VALUE")
    void testSubtract_Overflow_MinMinusOne() {
        assertEquals(Integer.MAX_VALUE, calculator.subtract(Integer.MIN_VALUE, 1));
    }

    // multiply tests

    @Test
    @DisplayName("multiply: Should multiply positive numbers")
    void testMultiply_PositiveNumbers() {
        assertEquals(15, calculator.multiply(3, 5));
    }

    @Test
    @DisplayName("multiply: Should multiply with zero")
    void testMultiply_WithZero() {
        assertEquals(0, calculator.multiply(0, 5));
        assertEquals(0, calculator.multiply(5, 0));
    }

    @Test
    @DisplayName("multiply: Should handle negative numbers")
    void testMultiply_NegativeNumbers() {
        assertEquals(6, calculator.multiply(-2, -3));
        assertEquals(-15, calculator.multiply(-3, 5));
        assertEquals(-15, calculator.multiply(3, -5));
    }

    @Test
    @DisplayName("multiply: Should overflow Integer.MAX_VALUE * 2 to -2")
    void testMultiply_Overflow_MaxTimesTwo() {
        assertEquals(-2, calculator.multiply(Integer.MAX_VALUE, 2));
    }

    @Test
    @DisplayName("multiply: Should overflow Integer.MIN_VALUE * -1 to Integer.MIN_VALUE")
    void testMultiply_Overflow_MinTimesMinusOne() {
        assertEquals(Integer.MIN_VALUE, calculator.multiply(Integer.MIN_VALUE, -1));
    }

    // divide tests

    @Test
    @DisplayName("divide: Should divide exactly")
    void testDivide_ExactResult() {
        assertEquals(2.0, calculator.divide(10, 5), 1e-9);
    }

    @Test
    @DisplayName("divide: Should produce non-integer result for 7 / 2")
    void testDivide_NonIntegerResult() {
        assertEquals(3.5, calculator.divide(7, 2), 1e-9);
    }

    @Test
    @DisplayName("divide: Should handle negative numbers")
    void testDivide_WithNegativeNumbers() {
        assertEquals(-3.0, calculator.divide(-9, 3), 1e-9);
        assertEquals(3.0, calculator.divide(-9, -3), 1e-9);
    }

    @Test
    @DisplayName("divide: Zero numerator should result in 0.0")
    void testDivide_ZeroNumerator() {
        assertEquals(0.0, calculator.divide(0, 5), 1e-9);
    }

    @Test
    @DisplayName("divide: Should throw IllegalArgumentException for division by zero")
    void testDivide_ByZero_ThrowsException() {
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () -> calculator.divide(10, 0));
        assertEquals("Cannot divide by zero", ex.getMessage());
    }

    @Test
    @DisplayName("divide: Should handle boundary values (Integer.MIN_VALUE / -1)")
    void testDivide_Boundary_MinValueDividedByMinusOne() {
        assertEquals(2147483648.0, calculator.divide(Integer.MIN_VALUE, -1), 1e-3);
    }
}
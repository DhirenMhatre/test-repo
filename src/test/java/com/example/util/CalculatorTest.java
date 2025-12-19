package com.example.util;

import com.example.util.Calculator;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("Calculator Tests")
class CalculatorTest {

    private static final double EPS = 1e-10;

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
        assertEquals(5, calculator.add(2, 3));
        assertEquals(100, calculator.add(40, 60));
    }

    @Test
    @DisplayName("add: with zero")
    void testAdd_WithZero() {
        assertEquals(5, calculator.add(5, 0));
        assertEquals(5, calculator.add(0, 5));
        assertEquals(0, calculator.add(0, 0));
    }

    @Test
    @DisplayName("add: negative numbers and mixed signs")
    void testAdd_NegativeNumbers() {
        assertEquals(-5, calculator.add(-2, -3));
        assertEquals(0, calculator.add(-5, 5));
        assertEquals(-1, calculator.add(-4, 3));
    }

    @Test
    @DisplayName("add: boundary values without overflow")
    void testAdd_Boundary_NoOverflow() {
        assertEquals(Integer.MAX_VALUE, calculator.add(Integer.MAX_VALUE, 0));
        assertEquals(Integer.MIN_VALUE, calculator.add(Integer.MIN_VALUE, 0));
    }

    // subtract

    @Test
    @DisplayName("subtract: two positive numbers")
    void testSubtract_PositiveNumbers() {
        assertEquals(2, calculator.subtract(5, 3));
        assertEquals(-20, calculator.subtract(40, 60));
    }

    @Test
    @DisplayName("subtract: result negative")
    void testSubtract_ResultNegative() {
        assertEquals(-2, calculator.subtract(3, 5));
    }

    @Test
    @DisplayName("subtract: with zero")
    void testSubtract_WithZero() {
        assertEquals(5, calculator.subtract(5, 0));
        assertEquals(-5, calculator.subtract(0, 5));
        assertEquals(0, calculator.subtract(0, 0));
    }

    @Test
    @DisplayName("subtract: negative numbers and mixed signs")
    void testSubtract_NegativeNumbers() {
        assertEquals(-2, calculator.subtract(-5, -3));
        assertEquals(-9, calculator.subtract(-4, 5));
        assertEquals(9, calculator.subtract(5, -4));
    }

    @Test
    @DisplayName("subtract: boundary values without overflow")
    void testSubtract_Boundary_NoOverflow() {
        assertEquals(Integer.MAX_VALUE, calculator.subtract(Integer.MAX_VALUE, 0));
        assertEquals(Integer.MIN_VALUE, calculator.subtract(Integer.MIN_VALUE, 0));
    }

    // multiply

    @Test
    @DisplayName("multiply: positive numbers")
    void testMultiply_PositiveNumbers() {
        assertEquals(15, calculator.multiply(3, 5));
        assertEquals(0, calculator.multiply(0, 100));
    }

    @Test
    @DisplayName("multiply: with zero")
    void testMultiply_WithZero() {
        assertEquals(0, calculator.multiply(7, 0));
        assertEquals(0, calculator.multiply(0, 7));
        assertEquals(0, calculator.multiply(0, 0));
    }

    @Test
    @DisplayName("multiply: negative numbers and mixed signs")
    void testMultiply_NegativeNumbers() {
        assertEquals(12, calculator.multiply(-4, -3));
        assertEquals(-12, calculator.multiply(-4, 3));
        assertEquals(-12, calculator.multiply(4, -3));
    }

    @Test
    @DisplayName("multiply: by one")
    void testMultiply_ByOne() {
        assertEquals(123, calculator.multiply(123, 1));
        assertEquals(123, calculator.multiply(1, 123));
        assertEquals(-123, calculator.multiply(-123, 1));
        assertEquals(-123, calculator.multiply(1, -123));
    }

    @Test
    @DisplayName("multiply: boundary values without overflow")
    void testMultiply_Boundary_NoOverflow() {
        assertEquals(Integer.MAX_VALUE, calculator.multiply(Integer.MAX_VALUE, 1));
        assertEquals(Integer.MIN_VALUE, calculator.multiply(Integer.MIN_VALUE, 1));
    }

    // divide

    @Test
    @DisplayName("divide: exact division")
    void testDivide_ExactDivision() {
        assertEquals(2.0, calculator.divide(10, 5), EPS);
        assertEquals(3.0, calculator.divide(9, 3), EPS);
    }

    @Test
    @DisplayName("divide: non-integer result")
    void testDivide_NonIntegerResult() {
        assertEquals(2.5, calculator.divide(5, 2), EPS);
        assertEquals(0.5, calculator.divide(1, 2), EPS);
    }

    @Test
    @DisplayName("divide: negative numbers yield positive result")
    void testDivide_NegativeNumbers_PositiveResult() {
        assertEquals(3.0, calculator.divide(-9, -3), EPS);
    }

    @Test
    @DisplayName("divide: mixed signs yield negative result")
    void testDivide_MixedSigns_NegativeResult() {
        assertEquals(-3.0, calculator.divide(-9, 3), EPS);
        assertEquals(-3.0, calculator.divide(9, -3), EPS);
    }

    @Test
    @DisplayName("divide: repeating decimal with tolerance")
    void testDivide_RepeatingDecimal() {
        assertEquals(1.0 / 3.0, calculator.divide(1, 3), EPS);
        assertEquals(2.0 / 3.0, calculator.divide(2, 3), EPS);
    }

    @Test
    @DisplayName("divide: by zero throws IllegalArgumentException with message")
    void testDivide_ByZero_ThrowsException() {
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () -> calculator.divide(10, 0));
        assertEquals("Cannot divide by zero", ex.getMessage());
    }
}
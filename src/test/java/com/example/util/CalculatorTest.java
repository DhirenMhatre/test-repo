package com.example.util;

import com.example.util.Calculator;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("Calculator Unit Tests")
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

    // add(int, int)

    @Test
    @DisplayName("add: Should add two positive numbers")
    void testAdd_PositiveNumbers() {
        assertEquals(9, calculator.add(4, 5));
    }

    @Test
    @DisplayName("add: Should handle zero correctly")
    void testAdd_WithZero() {
        assertEquals(7, calculator.add(7, 0));
        assertEquals(7, calculator.add(0, 7));
    }

    @Test
    @DisplayName("add: Should add negative numbers and mixed signs")
    void testAdd_NegativeNumbers() {
        assertEquals(-9, calculator.add(-4, -5));
        assertEquals(2, calculator.add(-3, 5));
        assertEquals(-2, calculator.add(3, -5));
        assertEquals(0, calculator.add(-5, 5));
    }

    @Test
    @DisplayName("add: Should overflow according to two's complement (MAX_VALUE + 1 -> MIN_VALUE)")
    void testAdd_Overflow() {
        int result = calculator.add(Integer.MAX_VALUE, 1);
        assertEquals(Integer.MIN_VALUE, result);
    }

    // subtract(int, int)

    @Test
    @DisplayName("subtract: Should subtract two positive numbers")
    void testSubtract_PositiveNumbers() {
        assertEquals(2, calculator.subtract(7, 5));
    }

    @Test
    @DisplayName("subtract: Should handle zero correctly")
    void testSubtract_WithZero() {
        assertEquals(7, calculator.subtract(7, 0));
        assertEquals(-7, calculator.subtract(0, 7));
    }

    @Test
    @DisplayName("subtract: Should subtract with negative numbers")
    void testSubtract_NegativeNumbers() {
        assertEquals(8, calculator.subtract(5, -3));
        assertEquals(-8, calculator.subtract(-5, 3));
        assertEquals(0, calculator.subtract(-5, -5));
    }

    @Test
    @DisplayName("subtract: Should underflow according to two's complement (MIN_VALUE - 1 -> MAX_VALUE)")
    void testSubtract_Underflow() {
        int result = calculator.subtract(Integer.MIN_VALUE, 1);
        assertEquals(Integer.MAX_VALUE, result);
    }

    // multiply(int, int)

    @Test
    @DisplayName("multiply: Should multiply two positive numbers")
    void testMultiply_PositiveNumbers() {
        assertEquals(35, calculator.multiply(7, 5));
    }

    @Test
    @DisplayName("multiply: Should handle multiplication by zero")
    void testMultiply_ByZero() {
        assertEquals(0, calculator.multiply(0, 12345));
        assertEquals(0, calculator.multiply(6789, 0));
    }

    @Test
    @DisplayName("multiply: Should handle negative numbers")
    void testMultiply_NegativeNumbers() {
        assertEquals(-15, calculator.multiply(-3, 5));
        assertEquals(-15, calculator.multiply(3, -5));
        assertEquals(15, calculator.multiply(-3, -5));
    }

    @Test
    @DisplayName("multiply: Should overflow according to two's complement (MAX_VALUE * 2 -> -2)")
    void testMultiply_Overflow() {
        int result = calculator.multiply(Integer.MAX_VALUE, 2);
        assertEquals(-2, result);
    }

    @Test
    @DisplayName("multiply: Edge overflow (MIN_VALUE * -1 -> MIN_VALUE due to overflow)")
    void testMultiply_MinValueTimesNegativeOne() {
        int result = calculator.multiply(Integer.MIN_VALUE, -1);
        assertEquals(Integer.MIN_VALUE, result);
    }

    // divide(int, int) -> double

    @Test
    @DisplayName("divide: Should divide evenly and return double result")
    void testDivide_ExactDivision() {
        double result = calculator.divide(10, 2);
        assertEquals(5.0, result, 1e-9);
    }

    @Test
    @DisplayName("divide: Should return fractional result for non-even division")
    void testDivide_FractionalResult() {
        double result = calculator.divide(1, 2);
        assertEquals(0.5, result, 1e-9);
    }

    @Test
    @DisplayName("divide: Should handle negative numbers")
    void testDivide_NegativeNumbers() {
        assertEquals(-1.5, calculator.divide(-3, 2), 1e-9);
        assertEquals(-1.5, calculator.divide(3, -2), 1e-9);
        assertEquals(1.5, calculator.divide(-3, -2), 1e-9);
    }

    @Test
    @DisplayName("divide: Should return 0.0 when numerator is zero")
    void testDivide_ZeroNumerator() {
        assertEquals(0.0, calculator.divide(0, 5), 1e-9);
        assertEquals(0.0, calculator.divide(0, -7), 1e-9);
    }

    @Test
    @DisplayName("divide: Should handle division by one and minus one")
    void testDivide_ByOneAndMinusOne() {
        assertEquals(42.0, calculator.divide(42, 1), 1e-9);
        assertEquals(-42.0, calculator.divide(42, -1), 1e-9);
    }

    @Test
    @DisplayName("divide: Should throw IllegalArgumentException when dividing by zero")
    void testDivide_ByZero_ThrowsIllegalArgumentException() {
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () -> calculator.divide(10, 0));
        assertEquals("Cannot divide by zero", ex.getMessage());
    }
}
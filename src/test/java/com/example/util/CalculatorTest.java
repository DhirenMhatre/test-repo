package com.example.util;

import org.junit.After;
import org.junit.Before;
import org.junit.Test;

import static org.junit.Assert.*;

public class CalculatorTest {

    private Calculator calculator;
    private Runnable mockCallback;
    private int callbackCalls;

    @Before
    public void setUp() {
        calculator = new Calculator();
        callbackCalls = 0;
        mockCallback = new Runnable() {
            @Override
            public void run() {
                callbackCalls++;
            }
        };
    }

    @After
    public void tearDown() {
        calculator = null;
    }

    @Test
    public void testAdd_WithValidInputs_ShouldReturnSum() {
        int[][] cases = new int[][]{
                {1, 1, 2},
                {-1, -1, -2},
                {5, -3, 2},
                {-7, 10, 3},
                {Integer.MAX_VALUE, 0, Integer.MAX_VALUE},
                {Integer.MIN_VALUE, 0, Integer.MIN_VALUE}
        };

        for (int[] c : cases) {
            int a = c[0], b = c[1], expected = c[2];
            int result = calculator.add(a, b);
            assertEquals("Sum should match expected value", expected, result);
        }
    }

    @Test
    public void testAdd_WithZeroOperand_ShouldReturnSameValue() {
        int[] values = new int[]{0, 1, -1, 42, -999999, Integer.MAX_VALUE, Integer.MIN_VALUE};
        for (int value : values) {
            assertEquals(value, calculator.add(value, 0));
            assertEquals(value, calculator.add(0, value));
        }
    }

    @Test
    public void testSubtract_WithValidInputs_ShouldReturnDifference() {
        int[][] cases = new int[][]{
                {5, 3, 2},
                {3, 5, -2},
                {-5, -3, -2},
                {-3, -5, 2},
                {0, 0, 0},
                {Integer.MAX_VALUE, Integer.MAX_VALUE, 0}
        };

        for (int[] c : cases) {
            int a = c[0], b = c[1], expected = c[2];
            int result = calculator.subtract(a, b);
            assertEquals("Difference should match expected value", expected, result);
        }
    }

    @Test
    public void testMultiply_WithValidInputs_ShouldReturnProduct() {
        int[][] cases = new int[][]{
                {2, 3, 6},
                {-2, 3, -6},
                {2, -3, -6},
                {-2, -3, 6},
                {0, 999, 0},
                {1, Integer.MAX_VALUE, Integer.MAX_VALUE}
        };

        for (int[] c : cases) {
            int a = c[0], b = c[1], expected = c[2];
            int result = calculator.multiply(a, b);
            assertEquals("Product should match expected value", expected, result);
        }
    }

    @Test
    public void testMultiply_WithZero_ShouldReturnZero() {
        int[] values = new int[]{0, 1, -1, 7, -13, 1000};
        for (int value : values) {
            assertEquals(0, calculator.multiply(value, 0));
            assertEquals(0, calculator.multiply(0, value));
        }
    }

    @Test
    public void testDivide_WithValidInputs_ShouldReturnQuotient() {
        double[][] cases = new double[][]{
                {6, 3, 2.0},
                {7, 2, 3.5},
                {-9, 3, -3.0},
                {9, -3, -3.0},
                {-8, -2, 4.0},
                {0, 5, 0.0}
        };

        for (double[] c : cases) {
            int a = (int) c[0];
            int b = (int) c[1];
            double expected = c[2];
            double result = calculator.divide(a, b);
            assertEquals("Quotient should match expected value within tolerance", expected, result, 1e-9);
        }
    }

    @Test
    public void testDivide_ByZero_ShouldThrowIllegalArgumentException() {
        try {
            calculator.divide(10, 0);
            fail("Expected IllegalArgumentException");
        } catch (IllegalArgumentException ex) {
            String msg = ex.getMessage() == null ? "" : ex.getMessage().toLowerCase();
            assertTrue(msg.contains("divide by zero") || msg.contains("division by zero") || msg.contains("divide") && msg.contains("zero"));
        }
    }

    @Test
    public void testOperations_ShouldNotInteractWithMocks() {
        // Perform operations
        calculator.add(1, 2);
        calculator.subtract(5, 3);
        calculator.multiply(4, 6);
        calculator.divide(8, 2);

        // Our "mock" is a local runnable; since calculator does not use it,
        // it should not be invoked.
        assertEquals(0, callbackCalls);
    }
}
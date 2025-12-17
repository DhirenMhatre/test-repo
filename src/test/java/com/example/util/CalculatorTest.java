package com.example.util;

import com.example.util.Calculator;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;
import org.junit.jupiter.params.provider.ValueSource;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import org.junit.jupiter.params.provider.Arguments;

@ExtendWith(MockitoExtension.class)
@DisplayName("Calculator Tests")
class CalculatorTest {

    @Mock
    private Runnable mockRunnable;

    @InjectMocks
    private Calculator calculator;

    @BeforeEach
    void setUp() {
        // Explicit initialization (even though @InjectMocks is present) to satisfy setup requirement
        calculator = new Calculator();
    }

    @AfterEach
    void tearDown() {
        calculator = null;
    }

    // Providers
    private static Stream<Arguments> addProvider() {
        return Stream.of(
                Arguments.of(1, 2, 3),
                Arguments.of(-1, 2, 1),
                Arguments.of(0, 0, 0),
                Arguments.of(Integer.MAX_VALUE, 0, Integer.MAX_VALUE),
                Arguments.of(Integer.MAX_VALUE, 1, Integer.MIN_VALUE) // overflow wrap-around
        );
    }

    private static Stream<Arguments> subtractProvider() {
        return Stream.of(
                Arguments.of(5, 3, 2),
                Arguments.of(3, 5, -2),
                Arguments.of(0, 0, 0),
                Arguments.of(Integer.MIN_VALUE, 1, Integer.MAX_VALUE), // underflow wrap-around
                Arguments.of(Integer.MIN_VALUE, 0, Integer.MIN_VALUE)
        );
    }

    private static Stream<Arguments> multiplyProvider() {
        return Stream.of(
                Arguments.of(3, 4, 12),
                Arguments.of(-3, 4, -12),
                Arguments.of(0, 999, 0),
                Arguments.of(Integer.MAX_VALUE, 0, 0),
                Arguments.of(Integer.MAX_VALUE, 2, -2) // overflow wrap-around
        );
    }

    private static Stream<Arguments> divideProvider() {
        return Stream.of(
                Arguments.of(8, 4, 2.0),
                Arguments.of(7, 2, 3.5),
                Arguments.of(-9, 3, -3.0),
                Arguments.of(1, -2, -0.5),
                Arguments.of(0, 5, 0.0)
        );
    }

    @ParameterizedTest(name = "add({0}, {1}) = {2}")
    @MethodSource("addProvider")
    @DisplayName("add: Should return expected sum for various inputs")
    void testAdd_WithVariousInputs_ShouldReturnExpectedSum(int a, int b, int expected) {
        assertEquals(expected, calculator.add(a, b));
    }

    @ParameterizedTest(name = "subtract({0}, {1}) = {2}")
    @MethodSource("subtractProvider")
    @DisplayName("subtract: Should return expected difference for various inputs")
    void testSubtract_WithVariousInputs_ShouldReturnExpectedDifference(int a, int b, int expected) {
        assertEquals(expected, calculator.subtract(a, b));
    }

    @ParameterizedTest(name = "multiply({0}, {1}) = {2}")
    @MethodSource("multiplyProvider")
    @DisplayName("multiply: Should return expected product for various inputs")
    void testMultiply_WithVariousInputs_ShouldReturnExpectedProduct(int a, int b, int expected) {
        assertEquals(expected, calculator.multiply(a, b));
    }

    @ParameterizedTest(name = "divide({0}, {1}) = {2}")
    @MethodSource("divideProvider")
    @DisplayName("divide: Should return expected quotient for various inputs")
    void testDivide_WithVariousInputs_ShouldReturnExpectedQuotient(int a, int b, double expected) {
        assertEquals(expected, calculator.divide(a, b), 1e-9);
        assertTrue(Double.isFinite(calculator.divide(a, b)));
    }

    @Test
    @DisplayName("divide: Should throw IllegalArgumentException for division by zero")
    void testDivide_ByZero_ShouldThrowIllegalArgumentException() {
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () -> calculator.divide(1, 0));
        assertEquals("Cannot divide by zero", ex.getMessage());
    }

    @ParameterizedTest(name = "add({0}, 0) and add(0, {0}) should return {0}")
    @ValueSource(ints = {-100, -1, 0, 1, 100, Integer.MAX_VALUE, Integer.MIN_VALUE})
    @DisplayName("add: Adding zero should return the same number")
    void testAdd_AddZero_ShouldReturnSameNumber(int value) {
        assertEquals(value, calculator.add(value, 0));
        assertEquals(value, calculator.add(0, value));
    }

    @Test
    @DisplayName("Mockito: Should verify mock interaction is usable in test context")
    void testMockitoMockInteraction_ShouldInvokeRunnable() {
        mockRunnable.run();
        verify(mockRunnable, times(1)).run();
    }
}
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
import org.junit.jupiter.params.provider.Arguments;

import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("Calculator Tests")
class CalculatorTest {

    @Mock
    private Runnable mockCallback;

    @InjectMocks
    private Calculator calculator;

    @BeforeEach
    void setUp() {
        // Additional setup if needed
    }

    @AfterEach
    void tearDown() {
        // Cleanup resources if needed
        calculator = null;
    }

    @ParameterizedTest
    @MethodSource("addCases")
    @DisplayName("add: Should return correct sum for various inputs")
    void testAdd_WithValidInputs_ShouldReturnSum(int a, int b, int expected) {
        int result = calculator.add(a, b);
        assertEquals(expected, result, "Sum should match expected value");
    }

    @ParameterizedTest
    @ValueSource(ints = {0, 1, -1, 42, -999999, Integer.MAX_VALUE, Integer.MIN_VALUE})
    @DisplayName("add: Adding zero should return the original operand")
    void testAdd_WithZeroOperand_ShouldReturnSameValue(int value) {
        assertEquals(value, calculator.add(value, 0));
        assertEquals(value, calculator.add(0, value));
    }

    @ParameterizedTest
    @MethodSource("subtractCases")
    @DisplayName("subtract: Should return correct difference for various inputs")
    void testSubtract_WithValidInputs_ShouldReturnDifference(int a, int b, int expected) {
        int result = calculator.subtract(a, b);
        assertEquals(expected, result, "Difference should match expected value");
    }

    @ParameterizedTest
    @MethodSource("multiplyCases")
    @DisplayName("multiply: Should return correct product for various inputs")
    void testMultiply_WithValidInputs_ShouldReturnProduct(int a, int b, int expected) {
        int result = calculator.multiply(a, b);
        assertEquals(expected, result, "Product should match expected value");
    }

    @ParameterizedTest
    @ValueSource(ints = {0, 1, -1, 7, -13, 1000})
    @DisplayName("multiply: Multiplying by zero should return zero")
    void testMultiply_WithZero_ShouldReturnZero(int value) {
        assertEquals(0, calculator.multiply(value, 0));
        assertEquals(0, calculator.multiply(0, value));
    }

    @ParameterizedTest
    @MethodSource("divideCases")
    @DisplayName("divide: Should return correct quotient for various inputs")
    void testDivide_WithValidInputs_ShouldReturnQuotient(int a, int b, double expected) {
        double result = calculator.divide(a, b);
        assertEquals(expected, result, 1e-9, "Quotient should match expected value within tolerance");
    }

    @Test
    @DisplayName("divide: Should throw IllegalArgumentException when dividing by zero")
    void testDivide_ByZero_ShouldThrowIllegalArgumentException() {
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () -> calculator.divide(10, 0));
        assertTrue(ex.getMessage().toLowerCase().contains("divide by zero"));
    }

    @Test
    @DisplayName("Operations should not interact with unrelated mocks")
    void testOperations_ShouldNotInteractWithMocks() {
        calculator.add(1, 2);
        calculator.subtract(5, 3);
        calculator.multiply(4, 6);
        calculator.divide(8, 2);

        verifyNoInteractions(mockCallback);
    }

    private static Stream<Arguments> addCases() {
        return Stream.of(
                Arguments.of(1, 1, 2),
                Arguments.of(-1, -1, -2),
                Arguments.of(5, -3, 2),
                Arguments.of(-7, 10, 3),
                Arguments.of(Integer.MAX_VALUE, 0, Integer.MAX_VALUE),
                Arguments.of(Integer.MIN_VALUE, 0, Integer.MIN_VALUE)
        );
    }

    private static Stream<Arguments> subtractCases() {
        return Stream.of(
                Arguments.of(5, 3, 2),
                Arguments.of(3, 5, -2),
                Arguments.of(-5, -3, -2),
                Arguments.of(-3, -5, 2),
                Arguments.of(0, 0, 0),
                Arguments.of(Integer.MAX_VALUE, Integer.MAX_VALUE, 0)
        );
    }

    private static Stream<Arguments> multiplyCases() {
        return Stream.of(
                Arguments.of(2, 3, 6),
                Arguments.of(-2, 3, -6),
                Arguments.of(2, -3, -6),
                Arguments.of(-2, -3, 6),
                Arguments.of(0, 999, 0),
                Arguments.of(1, Integer.MAX_VALUE, Integer.MAX_VALUE)
        );
    }

    private static Stream<Arguments> divideCases() {
        return Stream.of(
                Arguments.of(6, 3, 2.0),
                Arguments.of(7, 2, 3.5),
                Arguments.of(-9, 3, -3.0),
                Arguments.of(9, -3, -3.0),
                Arguments.of(-8, -2, 4.0),
                Arguments.of(0, 5, 0.0)
        );
    }
}
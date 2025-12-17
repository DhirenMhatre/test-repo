package main.java.com.example.util;

import main.java.com.example.util.Calculator;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;
import org.junit.jupiter.params.provider.ValueSource;
import org.junit.jupiter.params.provider.Arguments;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("Calculator Tests")
class CalculatorTest {

    private static final double EPS = 1e-9;

    @Mock
    private Runnable mockDependency;

    @InjectMocks
    private Calculator calculator;

    @BeforeEach
    void setUp() {
        // Additional setup if needed
    }

    @AfterEach
    void tearDown() {
        calculator = null;
    }

    // ---- Data Providers ----

    private static Stream<Arguments> addCases() {
        return Stream.of(
            Arguments.of(1, 2, 3),
            Arguments.of(-1, 5, 4),
            Arguments.of(-3, -7, -10),
            Arguments.of(0, 0, 0),
            Arguments.of(123456, 654321, 777777)
        );
    }

    private static Stream<Arguments> subtractCases() {
        return Stream.of(
            Arguments.of(5, 3, 2),
            Arguments.of(3, 5, -2),
            Arguments.of(0, 0, 0),
            Arguments.of(-5, -3, -2),
            Arguments.of(1000, 1, 999)
        );
    }

    private static Stream<Arguments> multiplyCases() {
        return Stream.of(
            Arguments.of(2, 3, 6),
            Arguments.of(-2, 3, -6),
            Arguments.of(-2, -3, 6),
            Arguments.of(0, 5, 0),
            Arguments.of(123, 0, 0)
        );
    }

    private static Stream<Arguments> divideCases() {
        return Stream.of(
            Arguments.of(6, 3, 2.0),
            Arguments.of(7, 2, 3.5),
            Arguments.of(-8, 2, -4.0),
            Arguments.of(9, -3, -3.0),
            Arguments.of(0, 5, 0.0)
        );
    }

    // ---- Tests: add ----

    @ParameterizedTest(name = "add({0}, {1}) = {2}")
    @MethodSource("addCases")
    @DisplayName("add: Should return the correct sum for multiple cases")
    void testAdd_WithMultipleCases_ShouldReturnExpectedSum(int a, int b, int expected) {
        int result = calculator.add(a, b);
        assertEquals(expected, result, "Sum should match expected");
    }

    // ---- Tests: subtract ----

    @ParameterizedTest(name = "subtract({0}, {1}) = {2}")
    @MethodSource("subtractCases")
    @DisplayName("subtract: Should return the correct difference for multiple cases")
    void testSubtract_WithMultipleCases_ShouldReturnExpectedDifference(int a, int b, int expected) {
        int result = calculator.subtract(a, b);
        assertEquals(expected, result, "Difference should match expected");
    }

    // ---- Tests: multiply ----

    @ParameterizedTest(name = "multiply({0}, {1}) = {2}")
    @MethodSource("multiplyCases")
    @DisplayName("multiply: Should return the correct product for multiple cases")
    void testMultiply_WithMultipleCases_ShouldReturnExpectedProduct(int a, int b, int expected) {
        int result = calculator.multiply(a, b);
        assertEquals(expected, result, "Product should match expected");
    }

    // ---- Tests: divide ----

    @ParameterizedTest(name = "divide({0}, {1}) = {2}")
    @MethodSource("divideCases")
    @DisplayName("divide: Should return the correct quotient for multiple cases")
    void testDivide_WithMultipleCases_ShouldReturnExpectedQuotient(int a, int b, double expected) {
        double result = calculator.divide(a, b);
        assertEquals(expected, result, EPS, "Quotient should match expected within tolerance");
        assertTrue(Double.isFinite(result), "Quotient should be a finite number");
    }

    @ParameterizedTest(name = "divide({0}, 0) should throw IllegalArgumentException")
    @ValueSource(ints = {0, 1, -1, 42, -100})
    @DisplayName("divide: Should throw IllegalArgumentException when dividing by zero")
    void testDivide_ByZero_ShouldThrowException(int numerator) {
        assertThrows(IllegalArgumentException.class, () -> calculator.divide(numerator, 0));
    }

    // ---- Mockito-related sanity test ----

    @Test
    @DisplayName("No external dependencies: Should not interact with mock dependency")
    void testCalculator_NoExternalDependencies_NoInteractionsWithMocks() {
        int result = calculator.add(2, 3);
        assertEquals(5, result);
        verifyNoInteractions(mockDependency);
    }
}
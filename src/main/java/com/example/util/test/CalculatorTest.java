package main.java.com.example.util;

import main.java.com.example.util.Calculator;
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
import static org.junit.jupiter.params.provider.Arguments.arguments;
import org.junit.jupiter.params.provider.Arguments;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("Calculator Tests")
class CalculatorTest {

    interface IntBinaryOp {
        int apply(int a, int b);
    }

    @Mock
    private IntBinaryOp mockedBinaryOp;

    @InjectMocks
    private Calculator calculator;

    @BeforeEach
    void setUp() {
        // No specific setup required for Calculator
    }

    @AfterEach
    void tearDown() {
        calculator = null;
    }

    static Stream<Arguments> addCases() {
        return Stream.of(
                arguments(0, 0, 0),
                arguments(1, 2, 3),
                arguments(-1, -2, -3),
                arguments(-5, 8, 3),
                arguments(1000, -250, 750)
        );
    }

    static Stream<Arguments> subtractCases() {
        return Stream.of(
                arguments(0, 0, 0),
                arguments(5, 3, 2),
                arguments(-5, -3, -2),
                arguments(-5, 3, -8),
                arguments(1000, -250, 1250)
        );
    }

    static Stream<Arguments> multiplyCases() {
        return Stream.of(
                arguments(0, 0, 0),
                arguments(0, 5, 0),
                arguments(3, 7, 21),
                arguments(-4, 6, -24),
                arguments(-4, -6, 24)
        );
    }

    static Stream<Arguments> divideCases() {
        return Stream.of(
                arguments(1, 1, 1.0),
                arguments(7, 2, 3.5),
                arguments(-9, 3, -3.0),
                arguments(-9, -3, 3.0),
                arguments(0, 5, 0.0)
        );
    }

    @ParameterizedTest(name = "add({0}, {1}) = {2}")
    @MethodSource("addCases")
    @DisplayName("add: Various inputs should produce expected sums")
    void testAdd_WithVariousInputs_ShouldReturnExpected(int a, int b, int expected) {
        assertEquals(expected, calculator.add(a, b));
    }

    @ParameterizedTest(name = "subtract({0}, {1}) = {2}")
    @MethodSource("subtractCases")
    @DisplayName("subtract: Various inputs should produce expected differences")
    void testSubtract_WithVariousInputs_ShouldReturnExpected(int a, int b, int expected) {
        assertEquals(expected, calculator.subtract(a, b));
    }

    @ParameterizedTest(name = "multiply({0}, {1}) = {2}")
    @MethodSource("multiplyCases")
    @DisplayName("multiply: Various inputs should produce expected products")
    void testMultiply_WithVariousInputs_ShouldReturnExpected(int a, int b, int expected) {
        assertEquals(expected, calculator.multiply(a, b));
    }

    @ParameterizedTest(name = "divide({0}, {1}) = {2}")
    @MethodSource("divideCases")
    @DisplayName("divide: Various inputs should produce expected quotients")
    void testDivide_WithVariousInputs_ShouldReturnExpected(int a, int b, double expected) {
        assertEquals(expected, calculator.divide(a, b), 1e-9);
    }

    @Test
    @DisplayName("divide: Division by zero should throw IllegalArgumentException")
    void testDivide_ByZero_ShouldThrowIllegalArgumentException() {
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () -> calculator.divide(10, 0));
        assertEquals("Cannot divide by zero", ex.getMessage());
    }

    @ParameterizedTest
    @ValueSource(ints = {-10, -1, 0, 1, 42, 1000})
    @DisplayName("add: Adding zero should return the same number")
    void testAdd_IdentityWithZero_ShouldReturnSameNumber(int val) {
        assertEquals(val, calculator.add(val, 0));
        assertEquals(val, calculator.add(0, val));
    }

    @ParameterizedTest
    @ValueSource(ints = {-10, -1, 0, 1, 42, 1000})
    @DisplayName("multiply: Multiplying by zero should return zero")
    void testMultiply_ByZero_ShouldReturnZero(int val) {
        assertEquals(0, calculator.multiply(val, 0));
        assertEquals(0, calculator.multiply(0, val));
    }

    static Stream<Arguments> commutativePairs() {
        return Stream.of(
                arguments(1, 2),
                arguments(-3, 5),
                arguments(-7, -4),
                arguments(0, 9),
                arguments(100, -25)
        );
    }

    @ParameterizedTest(name = "add commutative: add({0}, {1}) == add({1}, {0})")
    @MethodSource("commutativePairs")
    @DisplayName("add: Commutative property should hold")
    void testAdd_CommutativeProperty_ShouldHold(int a, int b) {
        assertEquals(calculator.add(a, b), calculator.add(b, a));
    }

    @ParameterizedTest(name = "multiply commutative: multiply({0}, {1}) == multiply({1}, {0})")
    @MethodSource("commutativePairs")
    @DisplayName("multiply: Commutative property should hold")
    void testMultiply_CommutativeProperty_ShouldHold(int a, int b) {
        assertEquals(calculator.multiply(a, b), calculator.multiply(b, a));
    }

    static Stream<Arguments> nonCommutativePairs() {
        return Stream.of(
                arguments(5, 3),
                arguments(-4, 9),
                arguments(0, 7),
                arguments(-8, -2)
        );
    }

    @ParameterizedTest(name = "subtract non-commutative: subtract({0}, {1}) != subtract({1}, {0}) when a != b")
    @MethodSource("nonCommutativePairs")
    @DisplayName("subtract: Non-commutative property should hold (a - b != b - a) for a != b")
    void testSubtract_NonCommutativeProperty_ShouldHold(int a, int b) {
        if (a != b) {
            assertNotEquals(calculator.subtract(a, b), calculator.subtract(b, a));
        }
    }

    @Test
    @DisplayName("Calculator operations should not interact with mocked dependencies (none present)")
    void testOperations_ShouldNotInteractWithMocks() {
        calculator.add(1, 2);
        calculator.subtract(5, 3);
        calculator.multiply(4, 6);
        calculator.divide(10, 2);

        verifyNoInteractions(mockedBinaryOp);
    }

    @Test
    @DisplayName("Basic sanity: Results follow expected sign rules")
    void testMultiply_SignRules_ShouldHold() {
        assertTrue(calculator.multiply(3, 5) > 0);
        assertTrue(calculator.multiply(-3, -5) > 0);
        assertTrue(calculator.multiply(-3, 5) < 0);
        assertEquals(0, calculator.multiply(0, 5));
    }
}
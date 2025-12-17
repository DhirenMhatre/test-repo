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
import static org.junit.jupiter.params.provider.Arguments.arguments;
import static org.mockito.Mockito.verifyNoInteractions;

import org.junit.jupiter.params.provider.Arguments;

@ExtendWith(MockitoExtension.class)
@DisplayName("Calculator Tests")
class CalculatorTest {

    @Mock
    private Runnable mockDependency;

    @InjectMocks
    private Calculator calculator;

    @BeforeEach
    void setUp() {
        assertNotNull(calculator, "Calculator should be initialized");
    }

    @AfterEach
    void tearDown() {
        // Calculator has no real dependencies; ensure we didn't interact with mock
        verifyNoInteractions(mockDependency);
        calculator = null;
    }

    private static Stream<Arguments> addCases() {
        return Stream.of(
                arguments(1, 2, 3),
                arguments(-1, -2, -3),
                arguments(0, 5, 5),
                arguments(100, -30, 70),
                arguments(-5, 10, 5)
        );
    }

    private static Stream<Arguments> addPairsForCommutativity() {
        return Stream.of(
                arguments(3, 7),
                arguments(-4, 10),
                arguments(0, 0),
                arguments(-2, -9),
                arguments(Integer.MAX_VALUE, -1)
        );
    }

    private static Stream<Arguments> subtractCases() {
        return Stream.of(
                arguments(10, 4, 6),
                arguments(-3, 6, -9),
                arguments(0, 5, -5),
                arguments(-8, -2, -6),
                arguments(5, 5, 0)
        );
    }

    private static Stream<Arguments> multiplyCases() {
        return Stream.of(
                arguments(3, 4, 12),
                arguments(0, 5, 0),
                arguments(-3, 6, -18),
                arguments(-4, -5, 20),
                arguments(7, 1, 7)
        );
    }

    private static Stream<Arguments> multiplyPairsForCommutativity() {
        return Stream.of(
                arguments(2, 9),
                arguments(-3, 7),
                arguments(0, 100),
                arguments(-6, -6),
                arguments(1, 999)
        );
    }

    private static Stream<Arguments> divideCases() {
        return Stream.of(
                arguments(8, 4, 2.0),
                arguments(7, 2, 3.5),
                arguments(-9, 3, -3.0),
                arguments(1, -2, -0.5),
                arguments(0, 5, 0.0)
        );
    }

    private static Stream<Arguments> finiteDividePairs() {
        return Stream.of(
                arguments(5, 2),
                arguments(-100, 3),
                arguments(1, Integer.MAX_VALUE),
                arguments(Integer.MIN_VALUE + 1, -2),
                arguments(42, 7)
        );
    }

    @ParameterizedTest
    @MethodSource("addCases")
    @DisplayName("testAdd_WithMultipleCases_ShouldReturnExpectedSum")
    void testAdd_WithMultipleCases_ShouldReturnExpectedSum(int a, int b, int expected) {
        assertEquals(expected, calculator.add(a, b));
    }

    @ParameterizedTest
    @MethodSource("addPairsForCommutativity")
    @DisplayName("testAdd_CommutativeProperty_ShouldHold")
    void testAdd_CommutativeProperty_ShouldHold(int a, int b) {
        assertEquals(calculator.add(a, b), calculator.add(b, a));
    }

    @ParameterizedTest
    @MethodSource("subtractCases")
    @DisplayName("testSubtract_WithMultipleCases_ShouldReturnExpectedDifference")
    void testSubtract_WithMultipleCases_ShouldReturnExpectedDifference(int a, int b, int expected) {
        assertEquals(expected, calculator.subtract(a, b));
    }

    @ParameterizedTest
    @MethodSource("multiplyCases")
    @DisplayName("testMultiply_WithMultipleCases_ShouldReturnExpectedProduct")
    void testMultiply_WithMultipleCases_ShouldReturnExpectedProduct(int a, int b, int expected) {
        assertEquals(expected, calculator.multiply(a, b));
    }

    @ParameterizedTest
    @ValueSource(ints = {-10, -1, 0, 1, 23, 1000})
    @DisplayName("testMultiply_WithZero_ShouldReturnZero")
    void testMultiply_WithZero_ShouldReturnZero(int a) {
        assertEquals(0, calculator.multiply(a, 0));
        assertEquals(0, calculator.multiply(0, a));
    }

    @ParameterizedTest
    @MethodSource("multiplyPairsForCommutativity")
    @DisplayName("testMultiply_CommutativeProperty_ShouldHold")
    void testMultiply_CommutativeProperty_ShouldHold(int a, int b) {
        assertEquals(calculator.multiply(a, b), calculator.multiply(b, a));
    }

    @ParameterizedTest
    @MethodSource("divideCases")
    @DisplayName("testDivide_WithValidInputs_ShouldReturnExpectedQuotient")
    void testDivide_WithValidInputs_ShouldReturnExpectedQuotient(int a, int b, double expected) {
        assertEquals(expected, calculator.divide(a, b), 1e-9);
    }

    @ParameterizedTest
    @ValueSource(ints = {0, 1, -1, 42, Integer.MAX_VALUE, Integer.MIN_VALUE + 1})
    @DisplayName("testDivide_ByZero_ShouldThrowIllegalArgumentException")
    void testDivide_ByZero_ShouldThrowIllegalArgumentException(int numerator) {
        assertThrows(IllegalArgumentException.class, () -> calculator.divide(numerator, 0));
    }

    @ParameterizedTest
    @MethodSource("finiteDividePairs")
    @DisplayName("testDivide_ResultIsFinite_ForValidInputs")
    void testDivide_ResultIsFinite_ForValidInputs(int a, int b) {
        double result = calculator.divide(a, b);
        assertTrue(Double.isFinite(result), "Result should be a finite double");
    }

    @Test
    @DisplayName("testSubtract_SameOperands_ShouldReturnZero")
    void testSubtract_SameOperands_ShouldReturnZero() {
        assertEquals(0, calculator.subtract(12345, 12345));
        assertEquals(0, calculator.subtract(-999, -999));
    }

    @Test
    @DisplayName("testAdd_WithZeroIdentity_ShouldReturnSameNumber")
    void testAdd_WithZeroIdentity_ShouldReturnSameNumber() {
        assertEquals(77, calculator.add(77, 0));
        assertEquals(-55, calculator.add(-55, 0));
        assertEquals(0, calculator.add(0, 0));
    }

    @Test
    @DisplayName("testMultiply_WithOneIdentity_ShouldReturnSameNumber")
    void testMultiply_WithOneIdentity_ShouldReturnSameNumber() {
        assertEquals(77, calculator.multiply(77, 1));
        assertEquals(-55, calculator.multiply(-55, 1));
        assertEquals(0, calculator.multiply(0, 1));
    }
}
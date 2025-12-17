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

    @InjectMocks
    private Calculator calculator;

    @Mock
    private Runnable mockRunnable;

    @BeforeEach
    void setUp() {
        assertNotNull(calculator, "Calculator should be initialized");
    }

    @AfterEach
    void tearDown() {
        calculator = null;
    }

    static Stream<Arguments> addData() {
        return Stream.of(
                Arguments.of(0, 0, 0),
                Arguments.of(1, 2, 3),
                Arguments.of(-1, -2, -3),
                Arguments.of(-5, 8, 3),
                Arguments.of(1000, -250, 750),
                Arguments.of(Integer.MAX_VALUE, 0, Integer.MAX_VALUE),
                Arguments.of(Integer.MIN_VALUE, 0, Integer.MIN_VALUE),
                Arguments.of(Integer.MAX_VALUE, -1, Integer.MAX_VALUE - 1)
        );
    }

    static Stream<Arguments> subtractData() {
        return Stream.of(
                Arguments.of(0, 0, 0),
                Arguments.of(5, 3, 2),
                Arguments.of(-5, -3, -2),
                Arguments.of(-5, 3, -8),
                Arguments.of(3, -5, 8),
                Arguments.of(Integer.MAX_VALUE, 1, Integer.MAX_VALUE - 1),
                Arguments.of(Integer.MIN_VALUE, -1, Integer.MIN_VALUE + 1)
        );
    }

    static Stream<Arguments> multiplyData() {
        return Stream.of(
                Arguments.of(0, 0, 0),
                Arguments.of(0, 5, 0),
                Arguments.of(1, 7, 7),
                Arguments.of(-1, 7, -7),
                Arguments.of(-3, -4, 12),
                Arguments.of(12, 12, 144),
                Arguments.of(Integer.MAX_VALUE, 1, Integer.MAX_VALUE),
                Arguments.of(Integer.MIN_VALUE, 1, Integer.MIN_VALUE)
        );
    }

    static Stream<Arguments> divideData() {
        return Stream.of(
                Arguments.of(0, 1, 0.0),
                Arguments.of(6, 3, 2.0),
                Arguments.of(5, 2, 2.5),
                Arguments.of(-5, 2, -2.5),
                Arguments.of(7, -2, -3.5),
                Arguments.of(-9, -3, 3.0)
        );
    }

    @ParameterizedTest(name = "add({0}, {1}) = {2}")
    @MethodSource("addData")
    @DisplayName("add(int, int): Should return correct sum")
    void testAdd_WithVariousInputs_ShouldReturnSum(int a, int b, int expected) {
        assertEquals(expected, calculator.add(a, b));
    }

    @ParameterizedTest(name = "subtract({0}, {1}) = {2}")
    @MethodSource("subtractData")
    @DisplayName("subtract(int, int): Should return correct difference")
    void testSubtract_WithVariousInputs_ShouldReturnDifference(int a, int b, int expected) {
        assertEquals(expected, calculator.subtract(a, b));
    }

    @ParameterizedTest(name = "multiply({0}, {1}) = {2}")
    @MethodSource("multiplyData")
    @DisplayName("multiply(int, int): Should return correct product")
    void testMultiply_WithVariousInputs_ShouldReturnProduct(int a, int b, int expected) {
        assertEquals(expected, calculator.multiply(a, b));
    }

    @ParameterizedTest(name = "divide({0}, {1}) = {2}")
    @MethodSource("divideData")
    @DisplayName("divide(int, int): Should return correct quotient")
    void testDivide_WithValidInputs_ShouldReturnQuotient(int a, int b, double expected) {
        assertEquals(expected, calculator.divide(a, b), 1e-9);
    }

    @Test
    @DisplayName("divide(int, int): Should throw IllegalArgumentException when dividing by zero")
    void testDivide_ByZero_ShouldThrowIllegalArgumentException() {
        assertThrows(IllegalArgumentException.class, () -> calculator.divide(1, 0));
        assertThrows(IllegalArgumentException.class, () -> calculator.divide(0, 0));
        assertThrows(IllegalArgumentException.class, () -> calculator.divide(-10, 0));
    }

    @ParameterizedTest(name = "a = {0} => add(a, 0) == a")
    @ValueSource(ints = {0, 1, -1, 42, -999999, Integer.MAX_VALUE, Integer.MIN_VALUE})
    @DisplayName("Identity: add(a, 0) should return a")
    void testIdentity_AdditionWithZero_ShouldReturnSameNumber(int a) {
        assertEquals(a, calculator.add(a, 0));
        assertEquals(a, calculator.add(0, a));
    }

    @ParameterizedTest(name = "a = {0} => multiply(a, 1) == a")
    @ValueSource(ints = {0, 1, -1, 13, -2048, Integer.MAX_VALUE, Integer.MIN_VALUE})
    @DisplayName("Identity: multiply(a, 1) should return a")
    void testIdentity_MultiplicationWithOne_ShouldReturnSameNumber(int a) {
        assertEquals(a, calculator.multiply(a, 1));
        assertEquals(a, calculator.multiply(1, a));
    }

    @Test
    @DisplayName("Commutative property: add and multiply should be commutative for sample values")
    void testCommutative_AdditionAndMultiplication_ShouldHold() {
        int[][] samples = {
                {2, 3}, {-4, 7}, {0, 5}, {-8, -9}, {Integer.MAX_VALUE, -1}
        };
        for (int[] pair : samples) {
            int a = pair[0], b = pair[1];
            assertEquals(calculator.add(a, b), calculator.add(b, a));
            assertEquals(calculator.multiply(a, b), calculator.multiply(b, a));
        }
    }

    @Test
    @DisplayName("Overflow behavior: add(Integer.MAX_VALUE, 1) should wrap to Integer.MIN_VALUE")
    void testAdd_WithOverflow_ShouldWrapAround() {
        int result = calculator.add(Integer.MAX_VALUE, 1);
        assertEquals(Integer.MIN_VALUE, result);
    }

    @Test
    @DisplayName("Mockito Spy: Should verify method invocation on Calculator")
    void testMethodInvocation_WithSpy_ShouldVerifyCall() {
        Calculator spyCalculator = spy(calculator);
        int res = spyCalculator.add(10, 5);
        assertEquals(15, res);
        verify(spyCalculator).add(10, 5);
        verifyNoMoreInteractions(spyCalculator);
    }

    @Test
    @DisplayName("Mockito Mock: Calculator should not interact with external mocks")
    void testNoInteractionsWithMocks_AfterOperations_ShouldHaveNoInteractions() {
        calculator.add(1, 2);
        calculator.subtract(5, 3);
        calculator.multiply(7, 6);
        calculator.divide(10, 2);

        verifyNoInteractions(mockRunnable);
    }
}
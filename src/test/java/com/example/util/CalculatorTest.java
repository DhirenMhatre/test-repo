package com.example.util;

import com.example.util.Calculator;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;
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

    private static final double EPS = 1e-9;

    interface OperationHook {
        void before(String operation, Number a, Number b);
    }

    static class CalculatorClient {
        private final OperationHook hook;

        CalculatorClient(OperationHook hook) {
            this.hook = hook;
        }

        int addInt(int a, int b) {
            hook.before("addInt", a, b);
            return Calculator.add(a, b);
        }

        double addDouble(double a, double b) {
            hook.before("addDouble", a, b);
            return Calculator.add(a, b);
        }
    }

    @Mock
    private OperationHook hook;

    @InjectMocks
    private CalculatorClient client;

    @BeforeEach
    void setUp() {
        assertNotNull(hook);
        assertNotNull(client);
    }

    @AfterEach
    void tearDown() {
        reset(hook);
    }

    // --------- Integer operations ---------

    static Stream<Arguments> intAddData() {
        return Stream.of(
                Arguments.of(0, 0, 0),
                Arguments.of(1, 2, 3),
                Arguments.of(-2, 5, 3),
                Arguments.of(100, -30, 70)
        );
    }

    @ParameterizedTest(name = "add({0}, {1}) = {2}")
    @MethodSource("intAddData")
    @DisplayName("add(int,int) - various pairs should return correct sum")
    void testAddInt_WithVariousPairs_ShouldReturnSum(int a, int b, int expected) {
        assertEquals(expected, Calculator.add(a, b));
    }

    static Stream<Arguments> intSubtractData() {
        return Stream.of(
                Arguments.of(0, 0, 0),
                Arguments.of(5, 3, 2),
                Arguments.of(-2, -5, 3),
                Arguments.of(10, 20, -10)
        );
    }

    @ParameterizedTest(name = "subtract({0}, {1}) = {2}")
    @MethodSource("intSubtractData")
    @DisplayName("subtract(int,int) - various pairs should return correct difference")
    void testSubtractInt_WithVariousPairs_ShouldReturnDifference(int a, int b, int expected) {
        assertEquals(expected, Calculator.subtract(a, b));
    }

    static Stream<Arguments> intMultiplyData() {
        return Stream.of(
                Arguments.of(0, 0, 0),
                Arguments.of(3, 4, 12),
                Arguments.of(-3, 4, -12),
                Arguments.of(-3, -4, 12)
        );
    }

    @ParameterizedTest(name = "multiply({0}, {1}) = {2}")
    @MethodSource("intMultiplyData")
    @DisplayName("multiply(int,int) - various pairs should return correct product")
    void testMultiplyInt_WithVariousPairs_ShouldReturnProduct(int a, int b, int expected) {
        assertEquals(expected, Calculator.multiply(a, b));
    }

    static Stream<Arguments> intDivideData() {
        return Stream.of(
                Arguments.of(7, 3, 2),
                Arguments.of(-7, 3, -2),
                Arguments.of(7, -3, -2),
                Arguments.of(-7, -3, 2),
                Arguments.of(1, 1, 1),
                Arguments.of(0, 5, 0)
        );
    }

    @ParameterizedTest(name = "divide({0}, {1}) = {2} (truncates toward zero)")
    @MethodSource("intDivideData")
    @DisplayName("divide(int,int) - should truncate toward zero")
    void testDivideInt_TruncatesTowardZero(int a, int b, int expected) {
        assertEquals(expected, Calculator.divide(a, b));
    }

    @Test
    @DisplayName("divide(int,int) - divide by zero should throw ArithmeticException")
    void testDivideInt_ByZero_ShouldThrowArithmeticException() {
        assertThrows(ArithmeticException.class, () -> Calculator.divide(1, 0));
    }

    // --------- Double operations ---------

    static Stream<Arguments> doubleAddData() {
        return Stream.of(
                Arguments.of(0.0, 0.0, 0.0),
                Arguments.of(1.2, 3.4, 4.6),
                Arguments.of(-2.5, 5.0, 2.5),
                Arguments.of(100.0, -30.25, 69.75)
        );
    }

    @ParameterizedTest(name = "add({0}, {1}) = {2}")
    @MethodSource("doubleAddData")
    @DisplayName("add(double,double) - various pairs should return correct sum")
    void testAddDouble_WithVariousPairs_ShouldReturnSum(double a, double b, double expected) {
        assertEquals(expected, Calculator.add(a, b), EPS);
    }

    static Stream<Arguments> doubleSubtractData() {
        return Stream.of(
                Arguments.of(0.0, 0.0, 0.0),
                Arguments.of(5.5, 3.2, 2.3),
                Arguments.of(-2.5, -5.5, 3.0),
                Arguments.of(10.0, 20.25, -10.25)
        );
    }

    @ParameterizedTest(name = "subtract({0}, {1}) = {2}")
    @MethodSource("doubleSubtractData")
    @DisplayName("subtract(double,double) - various pairs should return correct difference")
    void testSubtractDouble_WithVariousPairs_ShouldReturnDifference(double a, double b, double expected) {
        assertEquals(expected, Calculator.subtract(a, b), EPS);
    }

    static Stream<Arguments> doubleMultiplyData() {
        return Stream.of(
                Arguments.of(0.0, 0.0, 0.0),
                Arguments.of(3.0, 4.5, 13.5),
                Arguments.of(-3.0, 4.5, -13.5),
                Arguments.of(-3.0, -4.5, 13.5)
        );
    }

    @ParameterizedTest(name = "multiply({0}, {1}) = {2}")
    @MethodSource("doubleMultiplyData")
    @DisplayName("multiply(double,double) - various pairs should return correct product")
    void testMultiplyDouble_WithVariousPairs_ShouldReturnProduct(double a, double b, double expected) {
        assertEquals(expected, Calculator.multiply(a, b), EPS);
    }

    static Stream<Arguments> doubleDivideData() {
        return Stream.of(
                Arguments.of(9.0, 4.0, 2.25),
                Arguments.of(-9.0, 4.0, -2.25),
                Arguments.of(9.0, -4.0, -2.25),
                Arguments.of(-9.0, -4.5, 2.0),
                Arguments.of(0.0, 5.0, 0.0)
        );
    }

    @ParameterizedTest(name = "divide({0}, {1}) = {2}")
    @MethodSource("doubleDivideData")
    @DisplayName("divide(double,double) - various pairs should return correct quotient")
    void testDivideDouble_WithVariousPairs_ShouldReturnQuotient(double a, double b, double expected) {
        assertEquals(expected, Calculator.divide(a, b), EPS);
    }

    @Test
    @DisplayName("divide(double,double) - divide by zero should throw ArithmeticException")
    void testDivideDouble_ByZero_ShouldThrowArithmeticException() {
        assertThrows(ArithmeticException.class, () -> Calculator.divide(1.0, 0.0));
    }

    // --------- Mockito-based interaction test ---------

    @Test
    @DisplayName("CalculatorClient - should call hook before performing operation and return correct result")
    void testCalculatorClient_ShouldCallHookBeforeOperation() {
        int resultInt = client.addInt(3, 4);
        assertEquals(7, resultInt);
        verify(hook, times(1)).before("addInt", 3, 4);

        double resultDouble = client.addDouble(2.5, 0.5);
        assertEquals(3.0, resultDouble, EPS);
        verify(hook, times(1)).before("addDouble", 2.5, 0.5);
    }
}
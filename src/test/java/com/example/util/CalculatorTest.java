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

import java.util.function.IntSupplier;
import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import org.junit.jupiter.params.provider.Arguments;

@ExtendWith(MockitoExtension.class)
@DisplayName("Calculator Tests")
class CalculatorTest {

    @InjectMocks
    private Calculator calculator;

    private Calculator spyCalculator;

    @Mock
    private IntSupplier aSupplier;

    @Mock
    private IntSupplier bSupplier;

    @BeforeEach
    void setUp() {
        calculator = new Calculator();
        spyCalculator = spy(new Calculator());
    }

    @AfterEach
    void tearDown() {
        spyCalculator = null;
        calculator = null;
    }

    static Stream<Arguments> addCases() {
        return Stream.of(
                Arguments.of(0, 0, 0),
                Arguments.of(1, 2, 3),
                Arguments.of(-1, -2, -3),
                Arguments.of(-5, 10, 5),
                Arguments.of(1000, -100, 900)
        );
    }

    static Stream<Arguments> subtractCases() {
        return Stream.of(
                Arguments.of(0, 0, 0),
                Arguments.of(5, 2, 3),
                Arguments.of(-5, -2, -3),
                Arguments.of(-5, 10, -15),
                Arguments.of(10, -5, 15)
        );
    }

    static Stream<Arguments> multiplyCases() {
        return Stream.of(
                Arguments.of(0, 5, 0),
                Arguments.of(5, 0, 0),
                Arguments.of(3, 4, 12),
                Arguments.of(-3, 4, -12),
                Arguments.of(-3, -4, 12),
                Arguments.of(1, -7, -7)
        );
    }

    static Stream<Arguments> divideCases() {
        return Stream.of(
                Arguments.of(4, 2, 2.0),
                Arguments.of(7, 2, 3.5),
                Arguments.of(-9, 3, -3.0),
                Arguments.of(-10, -2, 5.0),
                Arguments.of(1, 3, 1.0 / 3.0)
        );
    }

    static Stream<Arguments> commutativePairs() {
        return Stream.of(
                Arguments.of(1, 2),
                Arguments.of(-5, 10),
                Arguments.of(-3, -7),
                Arguments.of(0, 42),
                Arguments.of(1000, -100)
        );
    }

    @ParameterizedTest
    @MethodSource("addCases")
    @DisplayName("add: Various inputs should return correct sum")
    void testAdd_WithVariousInputs_ShouldReturnSum(int a, int b, int expected) {
        assertEquals(expected, calculator.add(a, b));
    }

    @ParameterizedTest
    @MethodSource("subtractCases")
    @DisplayName("subtract: Various inputs should return correct difference")
    void testSubtract_WithVariousInputs_ShouldReturnDifference(int a, int b, int expected) {
        assertEquals(expected, calculator.subtract(a, b));
    }

    @ParameterizedTest
    @MethodSource("multiplyCases")
    @DisplayName("multiply: Various inputs should return correct product")
    void testMultiply_WithVariousInputs_ShouldReturnProduct(int a, int b, int expected) {
        assertEquals(expected, calculator.multiply(a, b));
    }

    @ParameterizedTest
    @MethodSource("divideCases")
    @DisplayName("divide: Valid inputs should return correct quotient")
    void testDivide_WithValidInputs_ShouldReturnQuotient(int a, int b, double expected) {
        double result = calculator.divide(a, b);
        assertEquals(expected, result, 1e-9);
    }

    @Test
    @DisplayName("divide: Dividing by zero should throw IllegalArgumentException")
    void testDivide_ByZero_ShouldThrowIllegalArgumentException() {
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () -> calculator.divide(10, 0));
        assertTrue(ex.getMessage().contains("divide by zero"));
    }

    @ParameterizedTest
    @ValueSource(ints = {-1000, -1, 0, 1, 1000})
    @DisplayName("add: Adding zero should return the same value")
    void testAdd_WithZeroIdentity_ShouldReturnSameValue(int value) {
        assertEquals(value, calculator.add(value, 0));
        assertEquals(value, calculator.add(0, value));
    }

    @ParameterizedTest
    @MethodSource("commutativePairs")
    @DisplayName("add: Commutative property should hold")
    void testAdd_CommutativeProperty_ShouldHold(int a, int b) {
        assertEquals(calculator.add(a, b), calculator.add(b, a));
    }

    @ParameterizedTest
    @MethodSource("commutativePairs")
    @DisplayName("multiply: Commutative property should hold")
    void testMultiply_CommutativeProperty_ShouldHold(int a, int b) {
        assertEquals(calculator.multiply(a, b), calculator.multiply(b, a));
    }

    @Test
    @DisplayName("Spy: Verify add method is invoked with correct arguments")
    void testSpyVerification_WhenCallingAdd_ShouldVerifyInvocation() {
        int result = spyCalculator.add(7, 8);
        assertEquals(15, result);
        verify(spyCalculator).add(7, 8);
        verifyNoMoreInteractions(spyCalculator);
    }

    @Test
    @DisplayName("Mockito: Should use mocked suppliers to provide inputs for add")
    void testAdd_WithMockedInputs_ShouldSumFromSuppliers() {
        when(aSupplier.getAsInt()).thenReturn(12);
        when(bSupplier.getAsInt()).thenReturn(30);

        int a = aSupplier.getAsInt();
        int b = bSupplier.getAsInt();
        int sum = calculator.add(a, b);

        assertEquals(42, sum);
        verify(aSupplier, times(1)).getAsInt();
        verify(bSupplier, times(1)).getAsInt();
        verifyNoMoreInteractions(aSupplier, bSupplier);
    }
}
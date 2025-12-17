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

import java.util.function.Supplier;
import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.*;
import static org.junit.jupiter.params.provider.Arguments.arguments;
import org.junit.jupiter.params.provider.Arguments;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("Calculator Tests")
class CalculatorTest {

    @Mock
    private Supplier<Integer> aSupplier;

    @Mock
    private Supplier<Integer> bSupplier;

    @InjectMocks
    private Calculator calculator;

    @BeforeEach
    void setUp() {
        // Ensure calculator is initialized even if @InjectMocks isn't effective in some environments
        this.calculator = new Calculator();
        assertNotNull(calculator, "Calculator should be instantiated before tests");
    }

    @AfterEach
    void tearDown() {
        this.calculator = null;
    }

    // -------------- Add tests --------------

    @Test
    @DisplayName("testAdd_WithValidInputs_ShouldReturnSum")
    void testAdd_WithValidInputs_ShouldReturnSum() {
        assertEquals(5, calculator.add(2, 3));
        assertEquals(0, calculator.add(-2, 2));
        assertEquals(-5, calculator.add(-2, -3));
    }

    @ParameterizedTest(name = "add({0}, {1}) == {2}")
    @MethodSource("provideAddCases")
    @DisplayName("testAdd_MultipleCases_ShouldMatchIntArithmetic")
    void testAdd_MultipleCases_ShouldMatchIntArithmetic(int a, int b, int expected) {
        assertEquals(expected, calculator.add(a, b));
    }

    static Stream<Arguments> provideAddCases() {
        return Stream.of(
                arguments(0, 0, 0),
                arguments(1, 2, 3),
                arguments(-1, 1, 0),
                arguments(Integer.MAX_VALUE, 0, Integer.MAX_VALUE),
                arguments(Integer.MIN_VALUE, 0, Integer.MIN_VALUE),
                arguments(Integer.MAX_VALUE, 1, Integer.MAX_VALUE + 1), // overflow expected
                arguments(Integer.MIN_VALUE, -1, Integer.MIN_VALUE - 1) // overflow expected
        );
    }

    @ParameterizedTest(name = "Commutativity: add({0}, {1}) == add({1}, {0})")
    @MethodSource("providePairCases")
    @DisplayName("testAdd_CommutativeProperty_Holds")
    void testAdd_CommutativeProperty_Holds(int a, int b) {
        assertEquals(calculator.add(a, b), calculator.add(b, a));
    }

    // -------------- Subtract tests --------------

    @Test
    @DisplayName("testSubtract_WithValidInputs_ShouldReturnDifference")
    void testSubtract_WithValidInputs_ShouldReturnDifference() {
        assertEquals(-1, calculator.subtract(2, 3));
        assertEquals(4, calculator.subtract(2, -2));
        assertEquals(1, calculator.subtract(-2, -3));
    }

    @ParameterizedTest(name = "subtract({0}, {1}) == {2}")
    @MethodSource("provideSubtractCases")
    @DisplayName("testSubtract_MultipleCases_ShouldMatchIntArithmetic")
    void testSubtract_MultipleCases_ShouldMatchIntArithmetic(int a, int b, int expected) {
        assertEquals(expected, calculator.subtract(a, b));
    }

    static Stream<Arguments> provideSubtractCases() {
        return Stream.of(
                arguments(0, 0, 0),
                arguments(1, 2, -1),
                arguments(-1, 1, -2),
                arguments(Integer.MAX_VALUE, 0, Integer.MAX_VALUE),
                arguments(Integer.MIN_VALUE, 0, Integer.MIN_VALUE),
                arguments(Integer.MIN_VALUE, 1, Integer.MIN_VALUE - 1), // overflow expected
                arguments(Integer.MAX_VALUE, -1, Integer.MAX_VALUE + 1) // overflow expected
        );
    }

    // -------------- Multiply tests --------------

    @Test
    @DisplayName("testMultiply_WithValidInputs_ShouldReturnProduct")
    void testMultiply_WithValidInputs_ShouldReturnProduct() {
        assertEquals(6, calculator.multiply(2, 3));
        assertEquals(-6, calculator.multiply(-2, 3));
        assertEquals(0, calculator.multiply(0, 999));
    }

    @ParameterizedTest(name = "multiply({0}, {1}) == {2}")
    @MethodSource("provideMultiplyCases")
    @DisplayName("testMultiply_MultipleCases_ShouldMatchIntArithmetic")
    void testMultiply_MultipleCases_ShouldMatchIntArithmetic(int a, int b, int expected) {
        assertEquals(expected, calculator.multiply(a, b));
    }

    static Stream<Arguments> provideMultiplyCases() {
        return Stream.of(
                arguments(0, 0, 0),
                arguments(1, 2, 2),
                arguments(-1, 2, -2),
                arguments(-3, -3, 9),
                arguments(Integer.MAX_VALUE, 1, Integer.MAX_VALUE),
                arguments(Integer.MIN_VALUE, 1, Integer.MIN_VALUE),
                arguments(10000, 10000, 100000000),
                arguments(Integer.MAX_VALUE, 2, Integer.MAX_VALUE * 2), // overflow expected
                arguments(Integer.MIN_VALUE, 2, Integer.MIN_VALUE * 2)  // overflow expected
        );
    }

    @ParameterizedTest(name = "Commutativity: multiply({0}, {1}) == multiply({1}, {0})")
    @MethodSource("providePairCases")
    @DisplayName("testMultiply_CommutativeProperty_Holds")
    void testMultiply_CommutativeProperty_Holds(int a, int b) {
        assertEquals(calculator.multiply(a, b), calculator.multiply(b, a));
    }

    // -------------- Divide tests --------------

    @Test
    @DisplayName("testDivide_WithValidInputs_ShouldReturnQuotient")
    void testDivide_WithValidInputs_ShouldReturnQuotient() {
        assertEquals(2.5, calculator.divide(5, 2), 1e-9);
        assertEquals(-2.5, calculator.divide(-5, 2), 1e-9);
        assertEquals(0.0, calculator.divide(0, 5), 1e-9);
    }

    @ParameterizedTest(name = "divide({0}, {1}) == {2}")
    @MethodSource("provideDivideCases")
    @DisplayName("testDivide_MultipleCases_ShouldMatchDoubleArithmetic")
    void testDivide_MultipleCases_ShouldMatchDoubleArithmetic(int a, int b, double expected) {
        assertEquals(expected, calculator.divide(a, b), 1e-9);
    }

    static Stream<Arguments> provideDivideCases() {
        return Stream.of(
                arguments(1, 2, 0.5),
                arguments(3, -2, -1.5),
                arguments(10, 5, 2.0),
                arguments(7, 3, 7.0 / 3.0),
                arguments(-7, -3, 7.0 / 3.0),
                arguments(0, 3, 0.0)
        );
    }

    @ParameterizedTest(name = "divide({0}, 0) should throw IllegalArgumentException")
    @ValueSource(ints = { -10, -1, 0, 1, 10, Integer.MAX_VALUE, Integer.MIN_VALUE })
    @DisplayName("testDivide_ByZero_ShouldThrowIllegalArgumentException")
    void testDivide_ByZero_ShouldThrowIllegalArgumentException(int numerator) {
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () -> calculator.divide(numerator, 0));
        assertTrue(ex.getMessage().contains("Cannot divide by zero"));
    }

    @Test
    @DisplayName("testDivide_WithNegativeDenominator_ShouldReturnNegativeResult")
    void testDivide_WithNegativeDenominator_ShouldReturnNegativeResult() {
        double result = calculator.divide(10, -2);
        assertEquals(-5.0, result, 1e-9);
    }

    // -------------- Mockito-driven tests using suppliers --------------

    @Test
    @DisplayName("testAdd_WithMockedSuppliers_ShouldUseProvidedOperands")
    void testAdd_WithMockedSuppliers_ShouldUseProvidedOperands() {
        when(aSupplier.get()).thenReturn(2);
        when(bSupplier.get()).thenReturn(3);

        int result = calculator.add(aSupplier.get(), bSupplier.get());

        assertEquals(5, result);
        verify(aSupplier, times(1)).get();
        verify(bSupplier, times(1)).get();
    }

    @Test
    @DisplayName("testDivide_WithMockedSuppliers_DenominatorZero_ShouldThrow")
    void testDivide_WithMockedSuppliers_DenominatorZero_ShouldThrow() {
        when(aSupplier.get()).thenReturn(42);
        when(bSupplier.get()).thenReturn(0);

        assertThrows(IllegalArgumentException.class, () -> calculator.divide(aSupplier.get(), bSupplier.get()));
        verify(aSupplier, times(1)).get();
        verify(bSupplier, times(1)).get();
    }

    // -------------- Common pair provider --------------

    static Stream<Arguments> providePairCases() {
        return Stream.of(
                arguments(0, 0),
                arguments(1, 2),
                arguments(-1, 2),
                arguments(100, -50),
                arguments(Integer.MAX_VALUE, -1),
                arguments(Integer.MIN_VALUE, 1)
        );
    }
}
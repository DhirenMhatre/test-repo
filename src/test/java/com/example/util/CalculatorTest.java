package com.example.util;

import com.example.util.Calculator;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;
import org.junit.jupiter.params.provider.Arguments;
import org.mockito.Mock;
import org.mockito.InjectMocks;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.junit.jupiter.api.Assertions.*;
import static org.junit.jupiter.params.provider.Arguments.arguments;
import static org.mockito.Mockito.*;

import java.util.stream.Stream;

@ExtendWith(MockitoExtension.class)
@DisplayName("Calculator Tests")
class CalculatorTest {

    interface DummyDependency {
        String doSomething();
    }

    @Mock
    private DummyDependency dummyDependency;

    @InjectMocks
    private Calculator calculator;

    @BeforeEach
    void setUp() {
        // Additional setup if needed
        assertNotNull(calculator, "Calculator should be injected and not null");
    }

    @AfterEach
    void tearDown() {
        // Teardown if needed
    }

    static Stream<Arguments> addCases() {
        return Stream.of(
                arguments(0, 0, 0),
                arguments(1, 1, 2),
                arguments(-1, 1, 0),
                arguments(-5, -7, -12),
                arguments(123456, 654321, 777777)
        );
    }

    static Stream<Arguments> subtractCases() {
        return Stream.of(
                arguments(0, 0, 0),
                arguments(5, 3, 2),
                arguments(3, 5, -2),
                arguments(-3, -5, 2),
                arguments(-10, 5, -15)
        );
    }

    static Stream<Arguments> multiplyCases() {
        return Stream.of(
                arguments(0, 0, 0),
                arguments(0, 5, 0),
                arguments(2, 3, 6),
                arguments(-2, 3, -6),
                arguments(-4, -5, 20)
        );
    }

    static Stream<Arguments> divideCases() {
        return Stream.of(
                arguments(1, 1, 1.0),
                arguments(5, 2, 2.5),
                arguments(-6, 3, -2.0),
                arguments(0, 5, 0.0),
                arguments(7, -2, -3.5)
        );
    }

    @ParameterizedTest(name = "add({0}, {1}) = {2}")
    @MethodSource("addCases")
    @DisplayName("add: multiple cases should return expected sums")
    void testAdd_WithMultipleCases_ShouldReturnExpected(int a, int b, int expected) {
        assertEquals(expected, calculator.add(a, b));
    }

    @Test
    @DisplayName("add: commutative property should hold")
    void testAdd_CommutativeProperty_ShouldHold() {
        int a = 7, b = -3;
        assertTrue(calculator.add(a, b) == calculator.add(b, a));
    }

    @ParameterizedTest(name = "subtract({0}, {1}) = {2}")
    @MethodSource("subtractCases")
    @DisplayName("subtract: multiple cases should return expected differences")
    void testSubtract_WithMultipleCases_ShouldReturnExpected(int a, int b, int expected) {
        assertEquals(expected, calculator.subtract(a, b));
    }

    @ParameterizedTest(name = "multiply({0}, {1}) = {2}")
    @MethodSource("multiplyCases")
    @DisplayName("multiply: multiple cases should return expected products")
    void testMultiply_WithMultipleCases_ShouldReturnExpected(int a, int b, int expected) {
        assertEquals(expected, calculator.multiply(a, b));
    }

    @ParameterizedTest(name = "divide({0}, {1}) = {2}")
    @MethodSource("divideCases")
    @DisplayName("divide: multiple cases should return expected quotients")
    void testDivide_WithMultipleCases_ShouldReturnExpected(int a, int b, double expected) {
        assertEquals(expected, calculator.divide(a, b), 1e-9);
    }

    @Test
    @DisplayName("divide: dividing by zero should throw IllegalArgumentException")
    void testDivide_ByZero_ShouldThrowIllegalArgumentException() {
        assertThrows(IllegalArgumentException.class, () -> calculator.divide(1, 0));
    }

    @Test
    @DisplayName("divide: result should be precise for non-integer quotient")
    void testDivide_WithNonIntegerResult_ShouldBePrecise() {
        double result = calculator.divide(5, 2);
        assertEquals(2.5, result, 1e-12);
    }

    @Test
    @DisplayName("multiply: should verify method invocation using spy")
    void testMultiply_WithSpy_ShouldVerifyInvocation() {
        Calculator spyCalc = spy(new Calculator());
        int product = spyCalc.multiply(3, 4);
        assertEquals(12, product);
        verify(spyCalc).multiply(3, 4);
    }

    @Test
    @DisplayName("Calculator instance should be initialized")
    void testConstructor_Default_ShouldInitialize() {
        assertNotNull(calculator);
    }
}
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
import static org.mockito.Mockito.*;
import org.junit.jupiter.params.provider.Arguments;

@ExtendWith(MockitoExtension.class)
@DisplayName("Calculator Tests")
class CalculatorTest {

    interface DummyService {
        void doSomething();
    }

    @Mock
    private DummyService dummyService;

    @InjectMocks
    private Calculator calculator;

    private Calculator calculatorSpy;

    @BeforeEach
    void setUp() {
        assertNotNull(calculator, "Calculator should be injected");
        calculatorSpy = spy(calculator);
    }

    @AfterEach
    void tearDown() {
        calculatorSpy = null;
    }

    static Stream<Arguments> addCases() {
        return Stream.of(
                Arguments.of(1, 2, 3),
                Arguments.of(-1, -5, -6),
                Arguments.of(-3, 7, 4),
                Arguments.of(0, 0, 0),
                Arguments.of(Integer.MAX_VALUE, 0, Integer.MAX_VALUE),
                Arguments.of(Integer.MAX_VALUE, -1, Integer.MAX_VALUE - 1),
                Arguments.of(Integer.MAX_VALUE, 1, Integer.MIN_VALUE) // overflow wrap
        );
    }

    static Stream<Arguments> subtractCases() {
        return Stream.of(
                Arguments.of(5, 3, 2),
                Arguments.of(3, 5, -2),
                Arguments.of(-5, -3, -2),
                Arguments.of(0, 0, 0),
                Arguments.of(Integer.MIN_VALUE, 1, Integer.MAX_VALUE) // underflow wrap
        );
    }

    static Stream<Arguments> multiplyCases() {
        return Stream.of(
                Arguments.of(3, 4, 12),
                Arguments.of(-3, 4, -12),
                Arguments.of(-3, -4, 12),
                Arguments.of(0, 999, 0),
                Arguments.of(Integer.MAX_VALUE, 1, Integer.MAX_VALUE),
                Arguments.of(Integer.MAX_VALUE, 2, -2) // overflow wrap
        );
    }

    static Stream<Arguments> divideCases() {
        return Stream.of(
                Arguments.of(4, 2, 2.0),
                Arguments.of(3, 2, 1.5),
                Arguments.of(-9, 3, -3.0),
                Arguments.of(0, 5, 0.0),
                Arguments.of(1, 3, 1.0 / 3.0)
        );
    }

    @ParameterizedTest(name = "add({0}, {1}) = {2}")
    @MethodSource("addCases")
    @DisplayName("add: multiple cases should return correct sums")
    void testAdd_WithMultipleCases_ShouldReturnExpectedSum(int a, int b, int expected) {
        assertEquals(expected, calculator.add(a, b));
    }

    @ParameterizedTest(name = "subtract({0}, {1}) = {2}")
    @MethodSource("subtractCases")
    @DisplayName("subtract: multiple cases should return correct differences")
    void testSubtract_WithMultipleCases_ShouldReturnExpectedDifference(int a, int b, int expected) {
        assertEquals(expected, calculator.subtract(a, b));
    }

    @ParameterizedTest(name = "multiply({0}, {1}) = {2}")
    @MethodSource("multiplyCases")
    @DisplayName("multiply: multiple cases should return correct products")
    void testMultiply_WithMultipleCases_ShouldReturnExpectedProduct(int a, int b, int expected) {
        assertEquals(expected, calculator.multiply(a, b));
    }

    @ParameterizedTest(name = "divide({0}, {1}) ≈ {2}")
    @MethodSource("divideCases")
    @DisplayName("divide: multiple cases should return correct double quotient")
    void testDivide_WithMultipleCases_ShouldReturnExpectedQuotient(int a, int b, double expected) {
        assertEquals(expected, calculator.divide(a, b), 1e-9);
    }

    @ParameterizedTest
    @ValueSource(ints = { -10, -1, 0, 1, 10, Integer.MAX_VALUE, Integer.MIN_VALUE })
    @DisplayName("add: adding zero should return the same number")
    void testAdd_WithZero_ShouldReturnSameNumber(int a) {
        assertEquals(a, calculator.add(a, 0));
        assertEquals(a, calculator.add(0, a));
    }

    @ParameterizedTest
    @ValueSource(ints = { -10, -1, 0, 1, 10, 123456 })
    @DisplayName("multiply: multiplying by zero should return zero")
    void testMultiply_WithZero_ShouldReturnZero(int a) {
        assertEquals(0, calculator.multiply(a, 0));
        assertEquals(0, calculator.multiply(0, a));
    }

    @ParameterizedTest
    @ValueSource(ints = { -10, -1, 0, 1, 10 })
    @DisplayName("divide: division by zero should throw IllegalArgumentException")
    void testDivide_ByZero_ShouldThrowIllegalArgumentException(int numerator) {
        assertThrows(IllegalArgumentException.class, () -> calculator.divide(numerator, 0));
    }

    @Test
    @DisplayName("add: spy should record method invocation")
    void testAdd_SpyInvocation_ShouldBeVerified() {
        int result = calculatorSpy.add(2, 3);
        assertEquals(5, result);
        verify(calculatorSpy, times(1)).add(2, 3);
    }

    @Test
    @DisplayName("multiply: commutativity property should hold for sample inputs")
    void testMultiply_Commutativity_ShouldHold() {
        assertEquals(calculator.multiply(3, 7), calculator.multiply(7, 3));
        assertEquals(calculator.multiply(-4, 5), calculator.multiply(5, -4));
        assertEquals(calculator.multiply(-6, -2), calculator.multiply(-2, -6));
    }

    @Test
    @DisplayName("add: commutativity property should hold for sample inputs")
    void testAdd_Commutativity_ShouldHold() {
        assertEquals(calculator.add(8, -3), calculator.add(-3, 8));
        assertEquals(calculator.add(0, 99), calculator.add(99, 0));
        assertEquals(calculator.add(-7, -1), calculator.add(-1, -7));
    }

    @Test
    @DisplayName("divide: negative by positive should yield negative result")
    void testDivide_NegativeByPositive_ShouldReturnNegative() {
        double result = calculator.divide(-10, 4);
        assertTrue(result < 0.0);
        assertEquals(-2.5, result, 1e-9);
    }

    @Test
    @DisplayName("No interactions with dummy service should occur")
    void testNoInteractions_WithDummyService() {
        verifyNoInteractions(dummyService);
    }
}
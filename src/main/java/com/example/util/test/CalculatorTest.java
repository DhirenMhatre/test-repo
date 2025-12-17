package main.java.com.example.util;

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
import static org.junit.jupiter.params.provider.Arguments.arguments;
import org.junit.jupiter.params.provider.Arguments;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("Calculator Tests")
class CalculatorTest {

    private static final double EPS = 1e-9;

    @InjectMocks
    private Calculator calculator;

    @Mock
    private Calculator calculatorMock;

    @BeforeEach
    void setUp() {
        // Setup if needed
        assertNotNull(calculator);
    }

    @AfterEach
    void tearDown() {
        // Teardown or reset mocks
        reset(calculatorMock);
    }

    static Stream<Arguments> addCases() {
        return Stream.of(
                arguments(1, 2),
                arguments(-1, 5),
                arguments(0, 0),
                arguments(Integer.MIN_VALUE, 1),
                arguments(Integer.MAX_VALUE, -1),
                arguments(-100, -200)
        );
    }

    @ParameterizedTest(name = "add({0}, {1}) should equal Java int addition")
    @MethodSource("addCases")
    @DisplayName("add - multiple cases")
    void testAdd_WithMultipleCases_ShouldReturnSum(int a, int b) {
        int expected = a + b;
        assertEquals(expected, calculator.add(a, b));
    }

    static Stream<Arguments> subtractCases() {
        return Stream.of(
                arguments(5, 3),
                arguments(3, 5),
                arguments(0, 0),
                arguments(-10, -20),
                arguments(Integer.MIN_VALUE, 1),
                arguments(Integer.MAX_VALUE, -1)
        );
    }

    @ParameterizedTest(name = "subtract({0}, {1}) should equal Java int subtraction")
    @MethodSource("subtractCases")
    @DisplayName("subtract - multiple cases")
    void testSubtract_WithMultipleCases_ShouldReturnDifference(int a, int b) {
        int expected = a - b;
        assertEquals(expected, calculator.subtract(a, b));
    }

    static Stream<Arguments> multiplyCases() {
        return Stream.of(
                arguments(2, 3),
                arguments(-2, 3),
                arguments(2, -3),
                arguments(-2, -3),
                arguments(0, 100),
                arguments(Integer.MAX_VALUE, 2),   // overflow behavior
                arguments(Integer.MIN_VALUE, -1)   // overflow behavior
        );
    }

    @ParameterizedTest(name = "multiply({0}, {1}) should equal Java int multiplication")
    @MethodSource("multiplyCases")
    @DisplayName("multiply - multiple cases including overflow behavior")
    void testMultiply_WithMultipleCases_ShouldReturnProduct(int a, int b) {
        int expected = a * b;
        assertEquals(expected, calculator.multiply(a, b));
    }

    static Stream<Arguments> divideCases() {
        return Stream.of(
                arguments(6, 3, 2.0),
                arguments(1, 2, 0.5),
                arguments(-4, 2, -2.0),
                arguments(4, -2, -2.0),
                arguments(-9, -3, 3.0),
                arguments(0, 5, 0.0),
                arguments(1, 3, 1.0 / 3.0)
        );
    }

    @ParameterizedTest(name = "divide({0}, {1}) should be approximately {2}")
    @MethodSource("divideCases")
    @DisplayName("divide - multiple valid cases")
    void testDivide_WithValidInputs_ShouldReturnQuotient(int a, int b, double expected) {
        double result = calculator.divide(a, b);
        assertEquals(expected, result, EPS);
        assertTrue(Double.isFinite(result));
    }

    @Test
    @DisplayName("divide - dividing by zero should throw IllegalArgumentException")
    void testDivide_ByZero_ShouldThrowIllegalArgumentException() {
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () -> calculator.divide(10, 0));
        assertEquals("Cannot divide by zero", ex.getMessage());
    }

    static class CalcUser {
        private final Calculator calculator;

        CalcUser(Calculator calculator) {
            this.calculator = calculator;
        }

        int sum(int a, int b) {
            return calculator.add(a, b);
        }
    }

    @Test
    @DisplayName("Should call Calculator.add via a dependent user class (Mockito verification)")
    void testCalcUser_ShouldCallDependency() {
        CalcUser user = new CalcUser(calculatorMock);
        when(calculatorMock.add(2, 3)).thenReturn(5);

        int result = user.sum(2, 3);

        assertEquals(5, result);
        verify(calculatorMock, times(1)).add(2, 3);
        verifyNoMoreInteractions(calculatorMock);
    }
}

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

    interface OperationLogger {
        void log(String message);
    }

    @Mock
    private OperationLogger operationLogger;

    @InjectMocks
    private Calculator calculator;

    @BeforeEach
    void setUp() {
        assertNotNull(calculator, "Calculator should be initialized");
    }

    @AfterEach
    void tearDown() {
        // No resources to clean up, but keeping for completeness
    }

    @Test
    @DisplayName("add: simple addition should return correct sum")
    void testAdd_WithValidInputs_ShouldReturnSum() {
        assertEquals(5, calculator.add(2, 3));
        assertEquals(0, calculator.add(-2, 2));
    }

    @ParameterizedTest(name = "add: {0} + {1} = {2}")
    @MethodSource("addCases")
    @DisplayName("add: parameterized cases")
    void testAdd_WithMultipleCases_ShouldReturnExpected(int a, int b, int expected) {
        assertEquals(expected, calculator.add(a, b));
    }

    @Test
    @DisplayName("subtract: simple subtraction should return correct difference")
    void testSubtract_WithValidInputs_ShouldReturnDifference() {
        assertEquals(-1, calculator.subtract(2, 3));
        assertEquals(-4, calculator.subtract(-2, 2));
    }

    @ParameterizedTest(name = "subtract: {0} - {1} = {2}")
    @MethodSource("subtractCases")
    @DisplayName("subtract: parameterized cases")
    void testSubtract_WithMultipleCases_ShouldReturnExpected(int a, int b, int expected) {
        assertEquals(expected, calculator.subtract(a, b));
    }

    @Test
    @DisplayName("multiply: simple multiplication should return correct product")
    void testMultiply_WithValidInputs_ShouldReturnProduct() {
        assertEquals(6, calculator.multiply(2, 3));
        assertEquals(-4, calculator.multiply(-2, 2));
        assertEquals(0, calculator.multiply(0, 100));
    }

    @ParameterizedTest(name = "multiply: {0} * {1} = {2}")
    @MethodSource("multiplyCases")
    @DisplayName("multiply: parameterized cases")
    void testMultiply_WithMultipleCases_ShouldReturnExpected(int a, int b, int expected) {
        assertEquals(expected, calculator.multiply(a, b));
    }

    @Test
    @DisplayName("divide: simple division should return correct quotient (double)")
    void testDivide_WithValidInputs_ShouldReturnQuotient() {
        assertEquals(2.5, calculator.divide(5, 2), 1e-9);
        assertEquals(-2.0, calculator.divide(-6, 3), 1e-9);
        assertEquals(0.0, calculator.divide(0, 5), 1e-9);
    }

    @ParameterizedTest(name = "divide: {0} / {1} = {2}")
    @MethodSource("divideCases")
    @DisplayName("divide: parameterized cases")
    void testDivide_WithMultipleCases_ShouldReturnExpected(int a, int b, double expected) {
        assertEquals(expected, calculator.divide(a, b), 1e-9);
    }

    @ParameterizedTest(name = "divide by zero should throw for numerator={0}")
    @ValueSource(ints = {0, 1, -5, Integer.MIN_VALUE, Integer.MAX_VALUE})
    @DisplayName("divide: division by zero should throw IllegalArgumentException")
    void testDivide_ByZero_ShouldThrowIllegalArgumentException(int numerator) {
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () -> calculator.divide(numerator, 0));
        assertTrue(ex.getMessage().toLowerCase().contains("zero"));
    }

    @Test
    @DisplayName("Mockito: spy should verify method invocation for add")
    void testAdd_SpyVerification_ShouldInvokeAdd() {
        Calculator spyCalc = spy(calculator);
        int result = spyCalc.add(7, 5);
        assertEquals(12, result);
        verify(spyCalc, times(1)).add(7, 5);
    }

    @Test
    @DisplayName("Mockito: mock should be created and usable")
    void testMockitoMock_Creation_ShouldSucceed() {
        assertNotNull(operationLogger);
        doNothing().when(operationLogger).log(anyString());
        operationLogger.log("test");
        verify(operationLogger).log("test");
    }

    private static Stream<Arguments> addCases() {
        return Stream.of(
                arguments(1, 2, 3),
                arguments(-1, 2, 1),
                arguments(-5, -7, -12),
                arguments(0, 0, 0),
                arguments(Integer.MAX_VALUE, -1, Integer.MAX_VALUE - 1)
        );
    }

    private static Stream<Arguments> subtractCases() {
        return Stream.of(
                arguments(5, 3, 2),
                arguments(3, 5, -2),
                arguments(-5, -7, 2),
                arguments(0, 0, 0),
                arguments(Integer.MIN_VALUE, 1, Integer.MIN_VALUE + 1)
        );
    }

    private static Stream<Arguments> multiplyCases() {
        return Stream.of(
                arguments(2, 3, 6),
                arguments(-2, 3, -6),
                arguments(-2, -3, 6),
                arguments(0, 100, 0),
                arguments(1000, 1000, 1_000_000)
        );
    }

    private static Stream<Arguments> divideCases() {
        return Stream.of(
                arguments(1, 1, 1.0),
                arguments(3, 2, 1.5),
                arguments(-6, 3, -2.0),
                arguments(5, -2, -2.5),
                arguments(0, 5, 0.0)
        );
    }
}
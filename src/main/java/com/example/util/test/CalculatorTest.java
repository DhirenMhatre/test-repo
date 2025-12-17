package main.java.com.example.util;

import main.java.com.example.util.Calculator;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.Arguments;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("Calculator Tests")
class CalculatorTest {

    @Mock
    private Runnable mockRunnable;

    @InjectMocks
    private Calculator calculator;

    @BeforeEach
    void setUp() {
        assertNotNull(calculator, "Calculator should be instantiated by @InjectMocks");
    }

    @AfterEach
    void tearDown() {
        clearInvocations(mockRunnable);
    }

    static Stream<Arguments> addCases() {
        return Stream.of(
                Arguments.of(1, 2, 3),
                Arguments.of(-1, 5, 4),
                Arguments.of(-3, -7, -10),
                Arguments.of(0, 0, 0),
                Arguments.of(Integer.MAX_VALUE, 0, Integer.MAX_VALUE),
                Arguments.of(Integer.MIN_VALUE, 1, Integer.MIN_VALUE + 1)
        );
    }

    static Stream<Arguments> subtractCases() {
        return Stream.of(
                Arguments.of(5, 3, 2),
                Arguments.of(3, 5, -2),
                Arguments.of(-3, -7, 4),
                Arguments.of(0, 0, 0),
                Arguments.of(Integer.MAX_VALUE, 1, Integer.MAX_VALUE - 1),
                Arguments.of(Integer.MIN_VALUE, -1, Integer.MIN_VALUE + 1)
        );
    }

    static Stream<Arguments> multiplyCases() {
        return Stream.of(
                Arguments.of(3, 4, 12),
                Arguments.of(-3, 4, -12),
                Arguments.of(-3, -4, 12),
                Arguments.of(0, 5, 0),
                Arguments.of(12345, 0, 0),
                Arguments.of(Integer.MAX_VALUE, 2, (int) ((long) Integer.MAX_VALUE * 2L))
        );
    }

    static Stream<Arguments> divideCases() {
        return Stream.of(
                Arguments.of(6, 3, 2.0),
                Arguments.of(1, 2, 0.5),
                Arguments.of(-9, 2, -4.5),
                Arguments.of(7, -3, -2.3333333333333335),
                Arguments.of(0, 5, 0.0)
        );
    }

    @ParameterizedTest(name = "add({0}, {1}) = {2}")
    @MethodSource("addCases")
    @DisplayName("add: Should return correct sum for various inputs")
    void testAdd_WithValidInputs_ShouldReturnSum(int a, int b, int expected) {
        int result = calculator.add(a, b);
        assertEquals(expected, result);
    }

    @ParameterizedTest(name = "subtract({0}, {1}) = {2}")
    @MethodSource("subtractCases")
    @DisplayName("subtract: Should return correct difference for various inputs")
    void testSubtract_WithValidInputs_ShouldReturnDifference(int a, int b, int expected) {
        int result = calculator.subtract(a, b);
        assertEquals(expected, result);
    }

    @ParameterizedTest(name = "multiply({0}, {1}) = {2}")
    @MethodSource("multiplyCases")
    @DisplayName("multiply: Should return correct product for various inputs")
    void testMultiply_WithValidInputs_ShouldReturnProduct(int a, int b, int expected) {
        int result = calculator.multiply(a, b);
        assertEquals(expected, result);
    }

    @ParameterizedTest(name = "divide({0}, {1}) = {2}")
    @MethodSource("divideCases")
    @DisplayName("divide: Should return correct quotient for various inputs")
    void testDivide_WithValidInputs_ShouldReturnQuotient(int a, int b, double expected) {
        double result = calculator.divide(a, b);
        assertEquals(expected, result, 1e-12);
    }

    @Test
    @DisplayName("divide: Should throw IllegalArgumentException when dividing by zero")
    void testDivide_ByZero_ShouldThrowIllegalArgumentException() {
        IllegalArgumentException ex = assertThrows(IllegalArgumentException.class, () -> calculator.divide(10, 0));
        assertEquals("Cannot divide by zero", ex.getMessage());
    }

    @ParameterizedTest
    @CsvSource({
            "1,2",
            "-4,7",
            "0,5",
            "100,-50"
    })
    @DisplayName("add: Should be commutative (a + b == b + a)")
    void testAdd_Commutative_ShouldHold(int a, int b) {
        assertEquals(calculator.add(a, b), calculator.add(b, a));
    }

    @ParameterizedTest
    @CsvSource({
            "5,0",
            "-12,0",
            "0,0",
            "123456,0"
    })
    @DisplayName("add: Adding zero should return the same number")
    void testAdd_AddingZero_ShouldReturnSameNumber(int a, int zero) {
        assertEquals(a, calculator.add(a, zero));
    }

    @ParameterizedTest
    @CsvSource({
            "5,1",
            "-12,1",
            "0,1",
            "123456,1"
    })
    @DisplayName("multiply: Multiplying by one should return the same number")
    void testMultiply_MultiplyingByOne_ShouldReturnSameNumber(int a, int one) {
        assertEquals(a, calculator.multiply(a, one));
    }

    @ParameterizedTest
    @CsvSource({
            "5,0,0",
            "-12,0,0",
            "0,0,0",
            "123456,0,0"
    })
    @DisplayName("multiply: Multiplying by zero should return zero")
    void testMultiply_MultiplyingByZero_ShouldReturnZero(int a, int b, int expected) {
        assertEquals(expected, calculator.multiply(a, b));
    }

    @ParameterizedTest
    @CsvSource({
            "10,3",
            "-10,3",
            "10,-3",
            "-10,-3"
    })
    @DisplayName("subtract: Should equal adding the negated second operand (a - b == a + (-b))")
    void testSubtract_RelationToAdd_ShouldHold(int a, int b) {
        assertEquals(calculator.subtract(a, b), calculator.add(a, -b));
    }

    @Test
    @DisplayName("Spy: Should verify method invocation on Calculator spy")
    void testSpy_OnCalculator_MethodInvocationVerified() {
        Calculator spyCalc = spy(new Calculator());
        int result = spyCalc.add(3, 4);
        assertEquals(7, result);
        verify(spyCalc, times(1)).add(3, 4);
    }

    @Test
    @DisplayName("Mock: Should verify mocked Runnable is invoked")
    void testMock_VerifyRunnableCalled() {
        mockRunnable.run();
        verify(mockRunnable, times(1)).run();
    }
}
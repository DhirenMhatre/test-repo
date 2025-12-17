package com.example.util;

import com.example.util.StringUtils;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;
import org.junit.jupiter.params.provider.ValueSource;
import org.junit.jupiter.params.provider.Arguments;
import org.mockito.Mock;
import org.mockito.InjectMocks;
import org.mockito.Spy;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.junit.jupiter.api.Assertions.*;
import static org.junit.jupiter.params.provider.Arguments.arguments;
import static org.mockito.Mockito.*;

import java.util.stream.Stream;

@ExtendWith(MockitoExtension.class)
@DisplayName("StringUtils Tests")
class StringUtilsTest {

    interface DependencyClass {
        String someMethod();
    }

    @Mock
    private DependencyClass mockDependency;

    @InjectMocks
    private StringUtils stringUtils;

    @Spy
    private StringUtils spyStringUtils;

    @BeforeEach
    void setUp() {
        // Additional setup if needed
    }

    @AfterEach
    void tearDown() {
        clearInvocations(mockDependency, spyStringUtils);
    }

    @Test
    @DisplayName("Constructor: Should initialize correctly with default constructor")
    void testConstructor_Default_ShouldInitialize() {
        StringUtils instance = new StringUtils();
        assertNotNull(instance);
    }

    @ParameterizedTest(name = "isEmpty(\"{0}\") should be true")
    @MethodSource("blankStrings")
    @DisplayName("isEmpty: Null and blank inputs should return true")
    void testIsEmpty_NullAndBlankInputs_ShouldReturnTrue(String input) {
        assertTrue(stringUtils.isEmpty(input));
    }

    static Stream<Arguments> blankStrings() {
        return Stream.of(
            arguments((String) null),
            arguments(""),
            arguments(" "),
            arguments("   "),
            arguments("\t"),
            arguments("\n"),
            arguments("\r\n"),
            arguments(" \t\n ")
        );
    }

    @ParameterizedTest(name = "isEmpty(\"{0}\") should be false")
    @ValueSource(strings = {"a", " abc ", "0", "\u00A0", "non-empty"})
    @DisplayName("isEmpty: Non-blank inputs should return false")
    void testIsEmpty_NonBlankInputs_ShouldReturnFalse(String input) {
        assertFalse(stringUtils.isEmpty(input));
    }

    @Test
    @DisplayName("reverse: Null input should return null")
    void testReverse_NullInput_ShouldReturnNull() {
        assertNull(stringUtils.reverse(null));
    }

    @ParameterizedTest(name = "reverse(\"{0}\") should be \"{1}\"")
    @MethodSource("reverseCases")
    @DisplayName("reverse: Various inputs should be reversed correctly")
    void testReverse_WithMultipleCases_ShouldReturnExpected(String input, String expected) {
        assertEquals(expected, stringUtils.reverse(input));
    }

    static Stream<Arguments> reverseCases() {
        return Stream.of(
            arguments("", ""),
            arguments("a", "a"),
            arguments("ab", "ba"),
            arguments("racecar", "racecar"),
            arguments("mañana", "anañam"),
            arguments("🙂a", "a🙂"),
            arguments("hello world", "dlrow olleh")
        );
    }

    @ParameterizedTest(name = "isPalindrome(\"{0}\") should be {1}")
    @MethodSource("palindromeCases")
    @DisplayName("isPalindrome: Should detect palindromes ignoring case and spaces")
    void testIsPalindrome_WithMultipleCases_ShouldReturnExpected(String input, boolean expected) {
        assertEquals(expected, stringUtils.isPalindrome(input));
    }

    static Stream<Arguments> palindromeCases() {
        return Stream.of(
            arguments(null, false),
            arguments("", true),
            arguments(" ", true),
            arguments("racecar", true),
            arguments("RaceCar", true),
            arguments("A man a plan a canal Panama", true),
            arguments("hello", false),
            arguments("Was it a car or a cat I saw", true)
        );
    }

    @ParameterizedTest(name = "countWords(\"{0}\") should be {1}")
    @MethodSource("countWordsCases")
    @DisplayName("countWords: Should count whitespace-delimited words correctly")
    void testCountWords_WithMultipleCases_ShouldReturnExpected(String input, int expected) {
        assertEquals(expected, stringUtils.countWords(input));
    }

    static Stream<Arguments> countWordsCases() {
        return Stream.of(
            arguments(null, 0),
            arguments("", 0),
            arguments("   ", 0),
            arguments("one", 1),
            arguments("one two three", 3),
            arguments(" one  two   three ", 3),
            arguments("hello,world", 1),
            arguments("hello\tworld\njava", 3)
        );
    }

    @Test
    @DisplayName("countWords: Should call isEmpty internally (verified using spy)")
    void testCountWords_BlankInput_ShouldInvokeIsEmptyUsingSpy() {
        int count = spyStringUtils.countWords("   ");
        assertEquals(0, count);
        verify(spyStringUtils, times(1)).isEmpty("   ");
    }

    @Test
    @DisplayName("countWords: Should propagate exception when isEmpty fails (using spy)")
    void testCountWords_WhenIsEmptyThrows_ShouldPropagateException() {
        doThrow(new IllegalStateException("boom")).when(spyStringUtils).isEmpty(any());
        assertThrows(IllegalStateException.class, () -> spyStringUtils.countWords("a b"));
        verify(spyStringUtils).isEmpty("a b");
    }

    @Test
    @DisplayName("reverse: Chaining on null result should throw NullPointerException")
    void testReverse_NullResultChaining_ShouldThrowNullPointerException() {
        assertThrows(NullPointerException.class, () -> stringUtils.reverse(null).length());
    }

    @Test
    @DisplayName("Should call dependency method correctly (Mockito mock demonstration)")
    void testDependency_ShouldCallDependency() {
        when(mockDependency.someMethod()).thenReturn("mocked");

        String result = mockDependency.someMethod();

        assertEquals("mocked", result);
        verify(mockDependency).someMethod();
    }
}
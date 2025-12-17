package com.example.util;

import com.example.util.StringUtils;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;
import org.junit.jupiter.params.provider.NullAndEmptySource;
import org.junit.jupiter.params.provider.ValueSource;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.Spy;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("StringUtils Tests")
class StringUtilsTest {

    interface DummyDependency {
        String compute(String input);
    }

    @Mock
    private DummyDependency dummyDependency;

    @InjectMocks
    private StringUtils stringUtils;

    @Spy
    private StringUtils spyStringUtils = new StringUtils();

    @BeforeEach
    void setUp() {
        assertNotNull(stringUtils, "StringUtils should be initialized by Mockito");
    }

    @AfterEach
    void tearDown() {
        // No resources to clean up, but demonstrate teardown hook
        stringUtils = null;
        dummyDependency = null;
        spyStringUtils = null;
    }

    // isEmpty tests
    @ParameterizedTest(name = "isEmpty with blank-or-null input ''{0}'' should return true")
    @NullAndEmptySource
    @ValueSource(strings = {" ", "\t", "\n", " \r\n "})
    @DisplayName("isEmpty - Null or whitespace-only should be true")
    void testIsEmpty_WithNullOrWhitespace_ShouldReturnTrue(String input) {
        assertTrue(stringUtils.isEmpty(input));
    }

    @ParameterizedTest(name = "isEmpty with non-empty input ''{0}'' should return false")
    @ValueSource(strings = {"a", " abc ", "0", "false"})
    @DisplayName("isEmpty - Non-empty strings should be false")
    void testIsEmpty_WithNonEmptyStrings_ShouldReturnFalse(String input) {
        assertFalse(stringUtils.isEmpty(input));
    }

    @Test
    @DisplayName("isEmpty - Non-breaking space should not be treated as blank by trim()")
    void testIsEmpty_WithNonBreakingSpace_ShouldReturnFalse() {
        String input = "\u00A0";
        assertFalse(stringUtils.isEmpty(input));
    }

    // reverse tests
    static Stream<String[]> reverseDataProvider() {
        return Stream.of(
                new String[]{"abc", "cba"},
                new String[]{"", ""},
                new String[]{"a", "a"},
                new String[]{"racecar", "racecar"},
                new String[]{" ab ", " ba "},
                new String[]{"a🙂", "🙂a"} // emoji surrogate pair
        );
    }

    @ParameterizedTest(name = "reverse ''{0}'' -> ''{1}''")
    @MethodSource("reverseDataProvider")
    @DisplayName("reverse - Should reverse strings correctly")
    void testReverse_WithVariousInputs_ShouldReturnReversed(String input, String expected) {
        assertEquals(expected, stringUtils.reverse(input));
    }

    @Test
    @DisplayName("reverse - Null input should return null")
    void testReverse_WithNull_ShouldReturnNull() {
        assertNull(stringUtils.reverse(null));
    }

    // isPalindrome tests
    @ParameterizedTest(name = "isPalindrome ''{0}'' should be true")
    @ValueSource(strings = {
            "racecar",
            "A man a plan a canal Panama",
            "nurses run",
            " Never odd or even ",
            ""
    })
    @DisplayName("isPalindrome - Palindromic strings should return true")
    void testIsPalindrome_WithPalindromes_ShouldReturnTrue(String input) {
        assertTrue(stringUtils.isPalindrome(input));
    }

    @ParameterizedTest(name = "isPalindrome ''{0}'' should be false")
    @ValueSource(strings = {"hello", "OpenAI", "Java", "palindrome", "no lemon, no melon?"})
    @DisplayName("isPalindrome - Non-palindromic strings should return false")
    void testIsPalindrome_WithNonPalindromes_ShouldReturnFalse(String input) {
        assertFalse(stringUtils.isPalindrome(input));
    }

    @Test
    @DisplayName("isPalindrome - Null input should return false")
    void testIsPalindrome_WithNull_ShouldReturnFalse() {
        assertFalse(stringUtils.isPalindrome(null));
    }

    // countWords tests
    @ParameterizedTest(name = "countWords ''{0}'' should be {1}")
    @MethodSource("countWordsDataProvider")
    @DisplayName("countWords - Should count words separated by whitespace")
    void testCountWords_WithVariousInputs_ShouldReturnExpected(String input, int expected) {
        assertEquals(expected, stringUtils.countWords(input));
    }

    static Stream<Object[]> countWordsDataProvider() {
        return Stream.of(
                new Object[]{null, 0},
                new Object[]{"", 0},
                new Object[]{"   ", 0},
                new Object[]{"\t \n", 0},
                new Object[]{"one", 1},
                new Object[]{"one two", 2},
                new Object[]{"  one   two three  ", 3},
                new Object[]{"hello, world!", 2},
                new Object[]{"line1\nline2\tline3", 3}
        );
    }

    @Test
    @DisplayName("countWords - Should delegate to isEmpty once")
    void testCountWords_ShouldCallIsEmptyOnce() {
        String input = "a b";
        int count = spyStringUtils.countWords(input);
        assertEquals(2, count);
        verify(spyStringUtils, times(1)).isEmpty(input);
    }

    @Test
    @DisplayName("countWords - If isEmpty throws, exception should propagate")
    void testCountWords_WhenIsEmptyThrows_ShouldPropagateException() {
        StringUtils localSpy = spy(new StringUtils());
        doThrow(new RuntimeException("boom")).when(localSpy).isEmpty(null);

        assertThrows(RuntimeException.class, () -> localSpy.countWords(null));
    }

    // Mockito usage and exception handling demonstration with mock
    @Test
    @DisplayName("Mockito - Mocked dependency can be stubbed and verified")
    void testMockitoMock_StubbingAndVerification() {
        when(dummyDependency.compute("in")).thenReturn("out");

        String result = dummyDependency.compute("in");

        assertEquals("out", result);
        verify(dummyDependency, times(1)).compute("in");
    }

    @Test
    @DisplayName("Mockito - Mocked dependency can throw exception and be asserted")
    void testMockitoMock_ShouldThrowAndBeAsserted() {
        when(dummyDependency.compute("bad")).thenThrow(new IllegalStateException("invalid"));

        assertThrows(IllegalStateException.class, () -> dummyDependency.compute("bad"));
        verify(dummyDependency, times(1)).compute("bad");
    }
}
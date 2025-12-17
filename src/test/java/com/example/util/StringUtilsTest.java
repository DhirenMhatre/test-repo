package com.example.util;

import com.example.util.StringUtils;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.Spy;
import org.mockito.junit.MockitoJUnitRunner;

import static org.junit.Assert.*;
import static org.mockito.Mockito.*;

@RunWith(MockitoJUnitRunner.class)
public class StringUtilsTest {

    interface DummyDependency {
        String compute(String input);
    }

    @Mock
    private DummyDependency dummyDependency;

    @InjectMocks
    private StringUtils stringUtils;

    @Spy
    private StringUtils spyStringUtils = new StringUtils();

    @Before
    public void setUp() {
        assertNotNull("StringUtils should be initialized by Mockito", stringUtils);
    }

    @After
    public void tearDown() {
        stringUtils = null;
        dummyDependency = null;
        spyStringUtils = null;
    }

    // isEmpty tests
    @Test
    public void testIsEmpty_WithNullOrWhitespace_ShouldReturnTrue() {
        String[] inputs = new String[]{null, "", " ", "\t", "\n", " \r\n "};
        for (String input : inputs) {
            assertTrue(stringUtils.isEmpty(input));
        }
    }

    @Test
    public void testIsEmpty_WithNonEmptyStrings_ShouldReturnFalse() {
        String[] inputs = new String[]{"a", " abc ", "0", "false"};
        for (String input : inputs) {
            assertFalse(stringUtils.isEmpty(input));
        }
    }

    @Test
    public void testIsEmpty_WithNonBreakingSpace_ShouldReturnFalse() {
        String input = "\u00A0";
        assertFalse(stringUtils.isEmpty(input));
    }

    // reverse tests
    @Test
    public void testReverse_WithVariousInputs_ShouldReturnReversed() {
        String[][] data = new String[][]{
                {"abc", "cba"},
                {"", ""},
                {"a", "a"},
                {"racecar", "racecar"},
                {" ab ", " ba "},
                {"a🙂", "🙂a"}
        };
        for (String[] pair : data) {
            String input = pair[0];
            String expected = pair[1];
            assertEquals(expected, stringUtils.reverse(input));
        }
    }

    @Test
    public void testReverse_WithNull_ShouldReturnNull() {
        assertNull(stringUtils.reverse(null));
    }

    // isPalindrome tests
    @Test
    public void testIsPalindrome_WithPalindromes_ShouldReturnTrue() {
        String[] inputs = new String[]{
                "racecar",
                "A man a plan a canal Panama",
                "nurses run",
                " Never odd or even ",
                ""
        };
        for (String input : inputs) {
            assertTrue(stringUtils.isPalindrome(input));
        }
    }

    @Test
    public void testIsPalindrome_WithNonPalindromes_ShouldReturnFalse() {
        String[] inputs = new String[]{"hello", "OpenAI", "Java", "palindrome", "no lemon, no melon?"};
        for (String input : inputs) {
            assertFalse(stringUtils.isPalindrome(input));
        }
    }

    @Test
    public void testIsPalindrome_WithNull_ShouldReturnFalse() {
        assertFalse(stringUtils.isPalindrome(null));
    }

    // countWords tests
    @Test
    public void testCountWords_WithVariousInputs_ShouldReturnExpected() {
        Object[][] data = new Object[][]{
                {null, 0},
                {"", 0},
                {"   ", 0},
                {"\t \n", 0},
                {"one", 1},
                {"one two", 2},
                {"  one   two three  ", 3},
                {"hello, world!", 2},
                {"line1\nline2\tline3", 3}
        };
        for (Object[] row : data) {
            String input = (String) row[0];
            int expected = (Integer) row[1];
            assertEquals(expected, stringUtils.countWords(input));
        }
    }

    @Test
    public void testCountWords_ShouldCallIsEmptyOnce() {
        String input = "a b";
        int count = spyStringUtils.countWords(input);
        assertEquals(2, count);
        verify(spyStringUtils, times(1)).isEmpty(input);
    }

    @Test
    public void testCountWords_WhenIsEmptyThrows_ShouldPropagateException() {
        StringUtils localSpy = spy(new StringUtils());
        doThrow(new RuntimeException("boom")).when(localSpy).isEmpty(null);

        try {
            localSpy.countWords(null);
            fail("Expected RuntimeException to be thrown");
        } catch (RuntimeException e) {
            // expected
        }
    }

    // Mockito usage and exception handling demonstration with mock
    @Test
    public void testMockitoMock_StubbingAndVerification() {
        when(dummyDependency.compute("in")).thenReturn("out");

        String result = dummyDependency.compute("in");

        assertEquals("out", result);
        verify(dummyDependency, times(1)).compute("in");
    }

    @Test
    public void testMockitoMock_ShouldThrowAndBeAsserted() {
        when(dummyDependency.compute("bad")).thenThrow(new IllegalStateException("invalid"));

        try {
            dummyDependency.compute("bad");
            fail("Expected IllegalStateException");
        } catch (IllegalStateException e) {
            assertEquals("invalid", e.getMessage());
        }
        verify(dummyDependency, times(1)).compute("bad");
    }
}
// skill vendor add の --allow-binary は位置引数のどこに置いても拾い、値の欠落は拒否する。
package command

import (
	"reflect"
	"testing"
)

func TestSplitAllowBinary(t *testing.T) {
	rest, allow, ok := splitAllowBinary([]string{"o/r", "--allow-binary", "a.png", "sub", "--allow-binary", "b.png"})
	if !ok || !reflect.DeepEqual(rest, []string{"o/r", "sub"}) || !reflect.DeepEqual(allow, []string{"a.png", "b.png"}) {
		t.Errorf("rest=%v allow=%v ok=%v", rest, allow, ok)
	}
	if _, _, ok := splitAllowBinary([]string{"o/r", "sub", "--allow-binary"}); ok {
		t.Error("値の無い --allow-binary を通した")
	}
}

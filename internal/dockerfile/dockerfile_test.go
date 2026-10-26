package dockerfile

import (
	"slices"
	"testing"
)

func TestParseStages(t *testing.T) {
	f, err := Parse("testdata/two-stage.Dockerfile")
	if err != nil {
		t.Fatal(err)
	}
	if len(f.Stages) != 2 {
		t.Fatalf("stage 數 = %d，要 2", len(f.Stages))
	}
	if got := f.Stages[0].FromArg; got != "MINIO_MC_IMAGE" {
		t.Errorf("Stages[0].FromArg = %q", got)
	}
	if got := f.Stages[1].FromArg; got != "ALPINE_SSHD_IMAGE" {
		t.Errorf("Stages[1].FromArg = %q", got)
	}
	if !slices.Contains(f.Stages[1].Args, "SEAWEEDFS_URL") {
		t.Errorf("Stages[1].Args = %v，應含 SEAWEEDFS_URL", f.Stages[1].Args)
	}
	if !slices.Contains(f.Stages[1].UsedVars, "SEAWEEDFS_URL") {
		t.Errorf("Stages[1].UsedVars = %v，應含 SEAWEEDFS_URL", f.Stages[1].UsedVars)
	}
	if want := []string{"MINIO_MC_IMAGE", "ALPINE_SSHD_IMAGE"}; !slices.Equal(f.GlobalArgs, want) {
		t.Errorf("GlobalArgs = %v，要 %v", f.GlobalArgs, want)
	}
	if f.Stages[1].Line != 7 {
		t.Errorf("Stages[1].Line = %d，要 7", f.Stages[1].Line)
	}
}

func TestParseDecls(t *testing.T) {
	f, err := Parse("testdata/two-stage.Dockerfile")
	if err != nil {
		t.Fatal(err)
	}
	var bare, def []string
	for _, a := range f.ArgDecls {
		if a.HasDefault {
			def = append(def, a.Name)
		} else {
			bare = append(bare, a.Name)
		}
	}
	if !slices.Contains(def, "LOCAL_DEFAULT") || slices.Contains(bare, "LOCAL_DEFAULT") {
		t.Errorf("LOCAL_DEFAULT 應是帶預設值的 ARG：bare=%v def=%v", bare, def)
	}
	if len(f.Envs) != 1 || f.Envs[0].Name != "FOO" {
		t.Errorf("Envs = %v", f.Envs)
	}
}

func TestHadolintBeforeArg(t *testing.T) {
	f, err := Parse("testdata/ignore-before-arg.Dockerfile")
	if err != nil {
		t.Fatal(err)
	}
	if want := []int{4}; !slices.Equal(f.IgnoreBeforeArg, want) {
		t.Errorf("IgnoreBeforeArg = %v，要 %v", f.IgnoreBeforeArg, want)
	}
}

func TestImageArgName(t *testing.T) {
	cases := [][3]string{
		{"alpine", "sshd", "ALPINE_SSHD_IMAGE"},
		{"alpine", "k8stools", "ALPINE_K8STOOLS_IMAGE"},
		{"my-fam", "a-b", "MY_FAM_A_B_IMAGE"},
	}
	for _, c := range cases {
		if got := ImageArgName(c[0], c[1]); got != c[2] {
			t.Errorf("ImageArgName(%q,%q) = %q，要 %q", c[0], c[1], got, c[2])
		}
	}
}

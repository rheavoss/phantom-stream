#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <mach-o/dyld.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

/*
 * Stealth launcher — compiled binary that embeds Python.
 * ps aux shows this binary name, not python3 + script path.
 * Looks up com.institute.backgroundsyncd in the same directory as itself.
 */

int main(void) {
    char exepath[4096] = {0};
    uint32_t sz = (uint32_t)sizeof(exepath);
    if (_NSGetExecutablePath(exepath, &sz) != 0) return 1;

    char *slash = strrchr(exepath, '/');
    if (!slash) return 1;

    char script[4096] = {0};
    size_t dirlen = (size_t)(slash - exepath + 1);
    memcpy(script, exepath, dirlen);
    memcpy(script + dirlen, "com.institute.backgroundsyncd",
           strlen("com.institute.backgroundsyncd") + 1);

    FILE *fp = fopen(script, "r");
    if (!fp) return 1;

    Py_Initialize();

    /* Set __file__ so os.path.abspath(__file__) works in server.py */
    PyObject *main_mod = PyImport_AddModule("__main__");
    if (main_mod) {
        PyObject *main_dict = PyModule_GetDict(main_mod);
        PyDict_SetItemString(main_dict, "__file__",
                             PyUnicode_DecodeFSDefault(script));
    }

    int rc = PyRun_SimpleFile(fp, script);
    fclose(fp);
    Py_Finalize();
    return rc == 0 ? 0 : 1;
}

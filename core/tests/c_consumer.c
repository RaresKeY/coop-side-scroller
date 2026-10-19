#include "ember_core.h"
#include <assert.h>
int main(void){
 EC_Handle *h=ec_v1_create(EC_ABI_V1,EC_ROLE_HOST,1);assert(h);
 EC_View v;assert(ec_v1_tick(h)==EC_OK);assert(ec_v1_read_view(h,&v,sizeof v)==EC_OK);
 assert(v.struct_size==sizeof v && v.tick==1);ec_v1_destroy(h);return 0;
}

#include "ember_core.h"
#include "ember_deterministic.h"
#include <assert.h>
int main(void){
 EC_Handle *h=ec_v1_create(EC_ABI_V1,EC_ROLE_HOST,1);assert(h);
 EC_View v;assert(ec_v1_tick(h)==EC_OK);assert(ec_v1_read_view(h,&v,sizeof v)==EC_OK);
 assert(v.struct_size==sizeof v && v.tick==1);ec_v1_destroy(h);
 const uint8_t session[16]={1};
 EC_Deterministic *d=ec_v1_deterministic_create(EC_ABI_V1,1,session,0,12);assert(d);
 assert(ec_v1_deterministic_input(d,1,1000,0)==EC_OK);
 assert(ec_v1_deterministic_advance(d,1)==EC_OK);
 EC_DeterministicStats stats;assert(ec_v1_deterministic_stats(d,&stats,sizeof stats)==EC_OK);
 assert(stats.tick==1 && stats.confirmed_tick==0);ec_v1_deterministic_destroy(d);return 0;
}

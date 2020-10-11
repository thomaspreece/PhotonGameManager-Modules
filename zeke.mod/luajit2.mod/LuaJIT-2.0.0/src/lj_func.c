/*
** Function handling (prototypes, functions and upvalues).
** Copyright (C) 2005-2010 Mike Pall. See Copyright Notice in luajit.h
**
** Portions taken verbatim or adapted from the Lua interpreter.
** Copyright (C) 1994-2008 Lua.org, PUC-Rio. See Copyright Notice in lua.h
*/

#define lj_func_c
#define LUA_CORE

#include "lj_obj.h"
#include "lj_gc.h"
#include "lj_func.h"
#include "lj_trace.h"
#include "lj_vm.h"

/* -- Prototypes ---------------------------------------------------------- */

void LJ_FASTCALL lj_func_freeproto(global_State *g, GCproto *pt)
{
  lj_trace_freeproto(g, pt);
  lj_mem_free(g, pt, pt->sizept);
}

/* -- Upvalues ------------------------------------------------------------ */

static void unlinkuv(GCupval *uv)
{
  lua_assert(uvprev(uvnext(uv)) == uv && uvnext(uvprev(uv)) == uv);
  setgcrefr(uvnext(uv)->prev, uv->prev);
  setgcrefr(uvprev(uv)->next, uv->next);
}

/* Find existing open upvalue for a stack slot or create a new one. */
static GCupval *func_finduv(lua_State *L, TValue *slot)
{
  global_State *g = G(L);
  GCRef *pp = &L->openupval;
  GCupval *p;
  GCupval *uv;
  /* Search the sorted list of open upvalues. */
  while (gcref(*pp) != NULL && uvval((p = gco2uv(gcref(*pp)))) >= slot) {
    lua_assert(!p->closed && uvval(p) != &p->tv);
    if (uvval(p) == slot) {  /* Found open upvalue pointing to same slot? */
      if (isdead(g, obj2gco(p)))  /* Resurrect it, if it's dead. */
	flipwhite(obj2gco(p));
      return p;
    }
    pp = &p->nextgc;
  }
  /* No matching upvalue found. Create a new one. */
  uv = lj_mem_newt(L, sizeof(GCupval), GCupval);
  newwhite(g, uv);
  uv->gct = ~LJ_TUPVAL;
  uv->closed = 0;  /* Still open. */
  setmref(uv->v, slot);  /* Pointing to the stack slot. */
  /* NOBARRIER: The GCupval is new (marked white) and open. */
  setgcrefr(uv->nextgc, *pp);  /* Insert into sorted list of open upvalues. */
  setgcref(*pp, obj2gco(uv));
  setgcref(uv->prev, obj2gco(&g->uvhead));  /* Insert into GC list, too. */
  setgcrefr(uv->next, g->uvhead.next);
  setgcref(uvnext(uv)->prev, obj2gco(uv));
  setgcref(g->uvhead.next, obj2gco(uv));
  lua_assert(uvprev(uvnext(uv)) == uv && uvnext(uvprev(uv)) == uv);
  return uv;
}

/* Close all open upvalues pointing to some stack level or above. */
void LJ_FASTCALL lj_func_closeuv(lua_State *L, TValue *level)
{
  GCupval *uv;
  global_State *g = G(L);
  while (gcref(L->openupval) != NULL &&
	 uvval((uv = gco2uv(gcref(L->openupval)))) >= level) {
    GCobj *o = obj2gco(uv);
    lua_assert(!isblack(o) && !uv->closed && uvval(uv) != &uv->tv);
    setgcrefr(L->openupval, uv->nextgc);  /* No longer in open list. */
    if (isdead(g, o)) {
      lj_func_freeuv(g, uv);
    } else {
      unlinkuv(uv);
      lj_gc_closeuv(g, uv);
    }
  }
}

void LJ_FASTCALL lj_func_freeuv(global_State *g, GCupval *uv)
{
  if (!uv->closed)
    unlinkuv(uv);
  lj_mem_freet(g, uv);
}

/* -- Functions (closures) ------------------------------------------------ */

GCfunc *lj_func_newC(lua_State *L, MSize nelems, GCtab *env)
{
  GCfunc *fn = cast(GCfunc *, lj_mem_newgco(L, sizeCfunc(nelems)));
  fn->c.gct = ~LJ_TFUNC;
  fn->c.ffid = FF_C;
  fn->c.nupvalues = cast_byte(nelems);
  /* NOBARRIER: The GCfunc is new (marked white). */
  setmref(fn->c.pc, &G(L)->bc_cfunc_ext);
  setgcref(fn->c.env, obj2gco(env));
  return fn;
}

GCfunc *lj_func_newL(lua_State *L, GCproto *pt, GCtab *env)
{
  GCfunc *fn = cast(GCfunc *, lj_mem_newgco(L, sizeLfunc((MSize)pt->sizeuv)));
  fn->l.gct = ~LJ_TFUNC;
  fn->l.ffid = FF_LUA;
  fn->l.nupvalues = cast_byte(pt->sizeuv);
  /* NOBARRIER: Really a setgcref. But the GCfunc is new (marked white). */
  setmref(fn->l.pc, proto_bc(pt));
  setgcref(fn->l.env, obj2gco(env));
  return fn;
}

/* Do a GC check and create a new Lua function with inherited upvalues. */
GCfunc *lj_func_newL_gc(lua_State *L, GCproto *pt, GCfuncL *parent)
{
  GCfunc *fn;
  GCRef *puv;
  uint32_t i, nuv;
  TValue *base;
  lj_gc_check_fixtop(L);
  fn = lj_func_newL(L, pt, tabref(parent->env));
  /* NOBARRIER: The GCfunc is new (marked white). */
  puv = parent->uvptr;
  nuv = fn->l.nupvalues;
  base = L->base;
  for (i = 0; i < nuv; i++) {
    uint32_t v = proto_uv(pt)[i];
    GCupval *uv;
    if ((v & 0x8000)) {
      uv = func_finduv(L, base + (v & 0xff));
      uv->dhash = (uint32_t)(uintptr_t)mref(parent->pc, char) ^ (v << 24);
    } else {
      uv = &gcref(puv[v])->uv;
    }
    setgcref(fn->l.uvptr[i], obj2gco(uv));
  }
  return fn;
}

void LJ_FASTCALL lj_func_free(global_State *g, GCfunc *fn)
{
  MSize size = isluafunc(fn) ? sizeLfunc((MSize)fn->l.nupvalues) :
			       sizeCfunc((MSize)fn->c.nupvalues);
  lj_mem_free(g, fn, size);
}


/* Sesión compartida de Mr. Fritas Gestión. No almacena contraseñas. */
window.MFSession={
  async get(role){
    const key="mf_gestion_session";
    let store=localStorage.getItem(key)?localStorage:sessionStorage;
    let raw=store.getItem(key);
    if(!raw)return null;
    let session;
    try{session=JSON.parse(raw)}catch(e){store.removeItem(key);return null}
    if(!session.access_token||!session.refresh_token)return null;
    const url="https://oiybkvtamrhjfcyfayes.supabase.co";
    const apiKey="sb_publishable_mGfgsfOujYYOBE0y6YZJ0g_jvAjdWVT";
    if(Number(session.expires_at||0)<Date.now()+90000){
      const response=await fetch(url+"/auth/v1/token?grant_type=refresh_token",{method:"POST",headers:{"apikey":apiKey,"Content-Type":"application/json"},body:JSON.stringify({refresh_token:session.refresh_token})});
      if(!response.ok)throw Error("Sesión vencida");
      const refreshed=await response.json();
      session={...session,access_token:refreshed.access_token,refresh_token:refreshed.refresh_token,expires_at:Date.now()+Number(refreshed.expires_in||3600)*1000,email:refreshed.user?.email||session.email};
      store.setItem(key,JSON.stringify(session));
    }
    const check=async name=>{
      const response=await fetch(url+"/rest/v1/rpc/has_staff_role",{method:"POST",headers:{"apikey":apiKey,"Authorization":"Bearer "+session.access_token,"Content-Type":"application/json"},body:JSON.stringify({p_role:name})});
      return response.ok&&(await response.json())===true;
    };
    if(!(await check(role))&&!(role!=="admin"&&await check("admin")))return null;
    return session.access_token;
  },
  clear(){localStorage.removeItem("mf_gestion_session");sessionStorage.removeItem("mf_gestion_session")}
};

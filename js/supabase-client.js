'use strict'

class SupabaseClient {
  constructor(options) {
    if (!options || !options.supabaseUrl || !options.supabaseAnonKey) {
      throw new Error('缺少必要的配置参数：supabaseUrl 和 supabaseAnonKey 必须提供')
    }

    this.supabaseUrl = options.supabaseUrl
    this.supabaseAnonKey = options.supabaseAnonKey
    this.client = null
    this.currentUser = null
    this.authStateListeners = []
    this.initialized = false
  }

  async init() {
    if (this.initialized) return

    if (typeof window.supabase === 'undefined') {
      throw new Error('Supabase SDK 未加载，请确保引入 @supabase/supabase-js')
    }

    this.client = window.supabase.createClient(this.supabaseUrl, this.supabaseAnonKey, {
      auth: {
        autoRefreshToken: true,
        persistSession: true,
        detectSessionInUrl: true,
        storage: window.localStorage
      },
      realtime: {
        params: {
          eventsPerSecond: 10
        }
      }
    })

    const { data: { session } } = await this.client.auth.getSession()
    if (session) {
      this.currentUser = session.user
      await this.loadUserProfile()
    }

    this.client.auth.onAuthStateChange(async (event, session) => {
      this.currentUser = session?.user || null
      
      if (event === 'SIGNED_IN' && this.currentUser) {
        await this.loadUserProfile()
      }
      
      this.authStateListeners.forEach(cb => cb(this.currentUser, event))
    })

    this.initialized = true
  }

  async loadUserProfile() {
    if (!this.currentUser) return null

    const { data, error } = await this.client
      .from('user_profiles')
      .select('*')
      .eq('id', this.currentUser.id)
      .single()

    if (error && error.code !== 'PGRST116') {
      console.error('加载用户配置失败:', error)
      return null
    }

    if (data) {
      this.userProfile = data
      return data
    }

    const { data: newProfile, error: createError } = await this.client
      .from('user_profiles')
      .insert({
        id: this.currentUser.id,
        username: this.currentUser.email?.split('@')[0] || `user_${Date.now()}`,
        avatar: `https://api.dicebear.com/7.x/avataaars/svg?seed=${this.currentUser.id}`
      })
      .select()
      .single()

    if (createError) {
      console.error('创建用户配置失败:', createError)
      return null
    }

    this.userProfile = newProfile
    return newProfile
  }

  onAuthStateChange(callback) {
    this.authStateListeners.push(callback)
    return () => {
      this.authStateListeners = this.authStateListeners.filter(cb => cb !== callback)
    }
  }

  getCurrentUser() {
    return this.currentUser
  }

  getUserProfile() {
    return this.userProfile
  }

  async signUp(username, password) {
    const { data, error } = await this.client.auth.signUp({
      email: `${username}@outlook.com`,
      password: password,
      options: {
        data: {
          username: username
        }
      }
    })

    if (error) throw error

    if (data.user) {
      const { error: profileError } = await this.client
        .from('user_profiles')
        .upsert({
          id: data.user.id,
          username: username,
          avatar: `https://api.dicebear.com/7.x/avataaars/svg?seed=${data.user.id}`
        })

      if (profileError) {
        console.error('创建用户配置失败:', profileError)
      }
    }

    return data
  }

  async signIn(username, password) {
    const { data, error } = await this.client.auth.signInWithPassword({
      email: `${username}@outlook.com`,
      password: password
    })

    if (error) throw error
    return data
  }

  async signOut() {
    const { error } = await this.client.auth.signOut()
    if (error) throw error
    this.currentUser = null
    this.userProfile = null
  }

  async createSay(content) {
    if (!this.currentUser || !this.userProfile) {
      throw new Error('用户未登录')
    }

    const { data, error } = await this.client
      .from('says')
      .insert({
        content: content,
        author_id: this.currentUser.id,
        username: this.userProfile.username,
        avatar: this.userProfile.avatar
      })
      .select()
      .single()

    if (error) throw error
    return data
  }

  async updateSay(sayId, content) {
    if (!this.currentUser) {
      throw new Error('用户未登录')
    }

    const { data, error } = await this.client
      .from('says')
      .update({ content: content })
      .eq('id', sayId)
      .eq('author_id', this.currentUser.id)
      .select()
      .single()

    if (error) throw error
    return data
  }

  async deleteSay(sayId) {
    if (!this.currentUser) {
      throw new Error('用户未登录')
    }

    const { error } = await this.client
      .from('says')
      .delete()
      .eq('id', sayId)
      .eq('author_id', this.currentUser.id)

    if (error) throw error
  }

  async getSays(page = 0, pageSize = 10) {
    const from = page * pageSize
    const to = from + pageSize - 1

    const { data, error, count } = await this.client
      .from('says')
      .select('*', { count: 'exact' })
      .order('created_at', { ascending: false })
      .range(from, to)

    if (error) throw error

    return {
      data: data,
      total: count,
      hasMore: count > (page + 1) * pageSize
    }
  }

  async getSayById(sayId) {
    const { data, error } = await this.client
      .from('says')
      .select('*')
      .eq('id', sayId)
      .single()

    if (error) throw error
    return data
  }

  subscribeToSays(callback) {
    const channel = this.client
      .channel('says-changes')
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'says'
        },
        (payload) => {
          callback(payload)
        }
      )
      .subscribe()

    return () => {
      this.client.removeChannel(channel)
    }
  }

  async uploadAvatar(file) {
    if (!this.currentUser) {
      throw new Error('用户未登录')
    }

    const fileExt = file.name.split('.').pop()
    const fileName = `${this.currentUser.id}/${Date.now()}.${fileExt}`

    const { error: uploadError } = await this.client
      .storage
      .from('avatars')
      .upload(fileName, file)

    if (uploadError) throw uploadError

    const { data: { publicUrl } } = this.client
      .storage
      .from('avatars')
      .getPublicUrl(fileName)

    const { error: updateError } = await this.client
      .from('user_profiles')
      .update({ avatar: publicUrl })
      .eq('id', this.currentUser.id)

    if (updateError) throw updateError

    this.userProfile.avatar = publicUrl
    return publicUrl
  }

  getClient() {
    return this.client
  }
}

window.SupabaseClient = SupabaseClient

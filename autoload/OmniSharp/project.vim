let s:save_cpo = &cpoptions
set cpoptions&vim

function! OmniSharp#project#CountLoaded() abort
  " TODO: stdio guard?
  let host = OmniSharp#GetHost()
  return get(OmniSharp#proc#GetJob(host.sln_or_dir), 'projects_loaded', 0)
endfunction

function! OmniSharp#project#CountTotal() abort
  " TODO: stdio guard?
  let host = OmniSharp#GetHost()
  return get(OmniSharp#proc#GetJob(host.sln_or_dir), 'projects_total', 0)
endfunction

" Listen for stdio server-loaded events
function! OmniSharp#project#ParseEvent(job, eventBody) abort
  if  g:OmniSharp_server_stdio_quickload

    " Quick load: Mark server as loaded as soon as configuration is finished
    if a:job.loaded | return | endif
    let message = get(a:eventBody, 'Message', '')
    if message ==# 'Configuration finished.'
      let a:job.loaded = 1
      silent doautocmd <nomodeline> User OmniSharpReady
      call OmniSharp#stdio#ReplayRequests()
    endif

  else

    " Complete load: Wait for all projects to be loaded before marking server as
    " loaded
    let projects_loaded = get(a:job, 'projects_loaded', 0)
    let projects_total = get(a:job, 'projects_total', 0)
    if a:job.loaded && projects_loaded == projects_total | return | endif

    if !has_key(a:job, 'loading_timeout')
      " Create a timeout to mark a job as loaded after 30 seconds despite not
      " receiving the expected server events.
      let a:job.loading_timeout = timer_start(
      \ g:OmniSharp_server_loading_timeout * 1000,
      \ function('s:ServerLoadTimeout', [a:job]))
    endif
    if !has_key(a:job, 'loading')
      let a:job.loading = []
    endif
    let name = get(a:eventBody, 'Name', '')
    let message = get(a:eventBody, 'Message', '')
    if name ==# 'OmniSharp.MSBuild.ProjectManager'
      let project = matchstr(message, '''\zs.*\ze''')
      if message =~# '^Queue project'
        call add(a:job.loading, project)
        if len(a:job.loading) > projects_total
          let a:job.projects_total = len(a:job.loading)
          silent doautocmd <nomodeline> User OmniSharpProjectUpdated
        endif
      endif
      if message =~# '^Successfully loaded project'
      \ || message =~# '^Failed to load project'
        if message[0] ==# 'F'
          echom 'Failed to load project: ' . project
        endif
        call filter(a:job.loading, {idx,val -> val !=# project})
        let a:job.projects_loaded = projects_loaded + 1
        silent doautocmd <nomodeline> User OmniSharpProjectUpdated
        if len(a:job.loading) == 0
          if g:OmniSharp_server_display_loading
            let elapsed = reltimefloat(reltime(a:job.start_time))
            echomsg printf('Loaded server for %s in %.1fs',
            \ a:job.sln_or_dir, elapsed)
          endif
          let a:job.loaded = 1
          silent doautocmd <nomodeline> User OmniSharpReady

          " TODO: Remove this delay once we have better information about
          " when the server is completely initialised:
          " https://github.com/OmniSharp/omnisharp-roslyn/issues/1521
          call timer_start(1000, function('OmniSharp#stdio#ReplayRequests'))
          " call OmniSharp#stdio#ReplayRequests()

          unlet a:job.loading
          call timer_stop(a:job.loading_timeout)
          unlet a:job.loading_timeout
        endif
      endif
    endif

  endif
endfunction

function! s:ServerLoadTimeout(job, timer) abort
  if g:OmniSharp_server_display_loading
    echomsg printf('Server load notification for %s not received after %d seconds - continuing.',
    \ a:job.sln_or_dir, g:OmniSharp_server_loading_timeout)
  endif
  let a:job.loaded = 1
  unlet a:job.loading
  unlet a:job.loading_timeout
  silent doautocmd <nomodeline> User OmniSharpReady
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo

" vim:et:sw=2:sts=2

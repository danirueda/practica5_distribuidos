# AUTOR: Daniel Rueda Macías
# NIA: 559207
# FICHERO: servidor_sa.exs
# TIEMPO: 37 horas
# DESCRIPCION: Servidor que gestiona el almacenamiento ante los clientes.
Code.require_file("#{__DIR__}/cliente_gv.exs")

defmodule ServidorSA do
    
    # estado local de cada nodo         
    defstruct num_vista: 0, primario: :undefined, copia: :undefined,
                bbdd: %{}, ultima_op: :undefined 


    @intervalo_latido 50


    @doc """
        Generar un estructura de datos estado inicial para nodo local
    """
    def iniciar_estado() do
       %ServidorSA{}
    end

    @doc """
        Obtener el hash de un string Elixir
         - Necesario pasar, previamente,  a formato string Erlang
         - Devuelve entero
    """
    def hash(string_concatenado) do
        String.to_charlist(string_concatenado) |> :erlang.phash2
    end


    @doc """
        Poner en marcha un servidor de almacenamiento
    """
    @spec start(String.t, String.t, node) :: node
    def start(host, nombre_nodo, nodo_servidor_gv) do
        nodo = NodoRemoto.start(host, nombre_nodo, __ENV__.file, __MODULE__)
        
        Node.spawn(nodo, __MODULE__, :init_sa, [nodo_servidor_gv])

        nodo
    end


    #------------------- Funciones privadas -----------------------------

    def init_sa(nodo_servidor_gv) do
        Process.register(self(), :servidor_sa)
        estado = iniciar_estado()
        bucle_recepcion_principal(estado, nodo_servidor_gv, :undefined) 
    end


    defp bucle_recepcion_principal(estado, nodo_servidor_gv, copia_anterior) do
        new_estado = receive do
            # Solicitudes de lectura y escritura de clientes del servicio 
            # de almacenamiento.
            {:lee, param, nodo_origen}  ->
                # Si soy el primario.
                if estado.primario == Node.self() do

                    # Si el copia ha cambiado y no es indefinido, 
                    # primario le manda su BBDD para que la cargue.
                    if (estado.copia != copia_anterior && 
                        estado.copia != :undefined) do
                        send({:servidor_sa, estado.copia}, {:carga_bbdd, 
                            estado.bbdd, Node.self()})
                    end

                    # Si la última operación ha sido leer lo mismo que en la actual.
                    if elem(estado.ultima_op, 0) == :lee && 
                    elem(estado.ultima_op, 1) == param do

                        # Mando el resultado de la operación anterior.
                        send({:cliente_sa, nodo_origen}, {:resultado, 
                            elem(estado.ultima_op, 2)})
                    else 

                        # Mando la lectura al copia.
                        send({:servidor_sa, estado.copia},{:lee, param, 
                            Node.self()})

                        # Espero autorización del copia para que primario pueda
                        # leer.
                        autorizacion = receive do
                            {:lectura_done, nodo_copia} ->
                                if nodo_copia == estado.copia do
                                    true
                                else
                                    false
                                end
                            after @intervalo_latido ->
                                false
                        end

                        # Si me da autorización el copia el primario lee, se alma-
                        # cena el resultado y lo envía al cliente.
                        if autorizacion do
                            resultado_lectura = Map.get(estado.bbdd, param)
                            estado = Map.put(estado, :ultima_op, {:lee, param, 
                                resultado_lectura})
                            send({:cliente_sa, nodo_origen},{:resultado, 
                                resultado_lectura})
                        else
                            send({:cliente_sa, nodo_origen},
                                "No se puede leer de la BBDD")
                        end
                    end
                end

                # Si soy el copia.
                if estado.copia == Node.self() do

                    # Si el primario es el nodo que envía la orden, se efectúa
                    # la lectura, se guarda el resultado y se envía una
                    # confirmación al primario.
                    if estado.primario == nodo_origen do
                        resultado_lectura = Map.get(estado.bbdd, param)
                        estado = Map.put(estado, :ultima_op, {:lee, param, 
                            resultado_lectura})
                        estado = Map.put(estado, :ultima_op, {:lee, param, 
                            resultado_lectura})
                        send({:servidor_sa, nodo_origen}, {:lectura_done, 
                            Node.self()})
                    end 
                end
                estado
            {:escribe_generico, param, nodo_origen} -> # Operación escribe con
                                                       # o sin hash.

                # Si soy el primario.
                if estado.primario == Node.self() do

                    # Si el copia ha cambiado y no es indefinido, 
                    # primario le manda su BBDD para que la cargue.
                    if (estado.copia != copia_anterior && 
                        estado.copia != :undefined) do
                        send({:servidor_sa, estado.copia}, {:carga_bbdd, 
                            estado.bbdd, Node.self()})
                    end

                    # Si la operación que me piden es distinta de la última.
                    if estado.ultima_op != {:escribe_generico, param} do

                        # Primero se manda la orden al copia para mantener el estado.
                        send({:servidor_sa, estado.copia},{:escribe_generico, 
                            param, Node.self()})

                        # Se espera autorización del copia.
                        autorizacion = receive do
                            {:escritura_done, nodo_copia} ->
                                if nodo_copia == estado.copia do
                                    true
                                else
                                    false
                                end
                            after @intervalo_latido ->
                                false
                        end

                        # Si da autorización entonces se procede a realizar la
                        # operación de escritura.
                        if autorizacion do # Si el copia ha actualizado
                                                     # bien su BBDD.

                            # Si es escritura con hash.
                            if elem(param, 2) do
                                antiguo_valor = Map.get(estado.bbdd, elem(param, 0))

                                # Si no hay un valor antiguo se escribe cadena vacía.
                                if antiguo_valor == nil do
                                    aux = Map.put(estado.bbdd, elem(param, 0), "")
                                    estado = Map.put(estado, :bbdd, aux)
                                else
                                    aux = Map.put(estado.bbdd, elem(param, 0), 
                                        hash(antiguo_valor <> elem(param, 1)))
                                    estado = Map.put(estado, :bbdd, aux)
                                end
                            else # Sin hash.

                                # Actualizo la BBDD.
                                aux = Map.put(estado.bbdd, elem(param, 0), 
                                    elem(param, 1))
                                estado = Map.put(estado, :bbdd, aux)
                            end

                            # Se guarda la última operación y se envía la confir-
                            # mación al cliente.
                            estado = Map.put(estado, :ultima_op, 
                                {:escribe_generico, param})
                            send({:cliente_sa, nodo_origen}, 
                                {:resultado, elem(param, 1)})      
                        else # Si no hay autorización se informa al cliente.
                            send({:cliente_sa, nodo_origen}, 
                                "No se puede actualizar la BBDD")
                        end 
                    end
                end

                # Si soy el copia y me mandan actualizar mi BBDD
                if estado.copia == Node.self() do # Si soy copia
                    if estado.primario == nodo_origen do

                        # Si es ecritura con hash
                        if elem(param, 2) do
                            antiguo_valor = Map.get(estado.bbdd, elem(param, 0))

                            # Si no hay un valor antiguo se escribe cadena vacía.
                            if antiguo_valor == nil do
                                aux = Map.put(estado.bbdd, elem(param, 0), "")
                                estado = Map.put(estado, :bbdd, aux)
                            else
                                aux = Map.put(estado.bbdd, elem(param, 0), 
                                    hash(antiguo_valor <> elem(param, 1)))
                                estado = Map.put(estado, :bbdd, aux)
                            end
                        else # Sin hash
                            aux = Map.put(estado.bbdd, elem(param, 0), 
                                elem(param, 1))
                            estado = Map.put(estado, :bbdd, aux)
                        end

                        # Se guarda el resultado de la última operación y manda
                        # confirmación al primario.
                        estado = Map.put(estado, :ultima_op, 
                            {:escribe_generico, param})
                        send({:servidor_sa, nodo_origen}, 
                            {:escritura_done, Node.self()})
                    end
                end
                estado
            {:carga_bbdd, bbdd, nodo_origen} ->

                # Si soy el copia y el primario me dice que actualice mi BBDD
                if (nodo_origen == estado.primario && 
                    estado.copia == Node.self()) do
                    estado = Map.put(estado, :bbdd, bbdd)
                end
                estado
        after @intervalo_latido ->

                # Cada @intervalo_latido se manda latido.
                {respuesta, is_ok} = ClienteGV.latido(nodo_servidor_gv, 
                    estado.num_vista)

                # Si todo está ok.
                if is_ok do
                    copia_anterior = estado.copia
                    estado = Map.put(estado, :num_vista, respuesta.num_vista)
                    estado = Map.put(estado, :primario, respuesta.primario)
                    Map.put(estado, :copia, respuesta.copia)
                end
        end
        bucle_recepcion_principal(new_estado, nodo_servidor_gv, copia_anterior)
    end
end